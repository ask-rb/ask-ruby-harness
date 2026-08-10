# frozen_string_literal: true

require "json"
require "active_support/core_ext/string/filters"

module Ask
  module Ruby
    module Harness
      # Append-only audit log for tool executions.
      #
      # Every tool call made by an agent is recorded in the +ask_audit_logs+
      # table (when one is available) with the intent (sanitized params) and
      # outcome (status, timing), but not the data returned. A
      # +audit_log.ask_ruby_harness+ ActiveSupport notification fires either
      # way, so hosts can subscribe without the table.
      #
      # Sensitive param values (keys matching +password+, +secret+, +token+,
      # +api_key+, +key+) are automatically redacted before logging.
      module AuditLog
        SENSITIVE_KEYS = /\A(password|secret|token|api_key|key|auth_token|access_token)\z/i

        class << self
          # Log a tool execution event.
          #
          # @param session_id [String] The agent session that triggered this call
          # @param tool_name [String] Name of the tool that ran
          # @param params [Hash] The parameters passed to the tool (sanitized automatically)
          # @param result [Ask::Result, Hash, nil] The result returned by the tool
          # @param error [StandardError, nil] The exception if the tool raised
          # @param duration_ms [Integer] Wall-clock time for the tool execution
          # @param user_context [Hash, nil] Who initiated the session (from config)
          def log(session_id:, tool_name:, params:, result: nil, error: nil, duration_ms:)
            now = Time.now.utc
            entry = {
              session_id: session_id,
              tool_name: tool_name,
              params: sanitize_params(params),
              result_summary: build_summary(tool_name, result, error),
              status: determine_status(result, error),
              error_message: determine_error(result, error),
              duration_ms: duration_ms,
              user_context: resolve_user_context,
              environment: environment_name,
              recorded_at: now,
              created_at: now,
              updated_at: now
            }

            if table_exists?
              write_entry(entry)
            end

            # Fire an ActiveSupport notification so host apps can subscribe
            ActiveSupport::Notifications.instrument("audit_log.ask_ruby_harness", entry)

            entry
          end

          private

          def sanitize_params(params)
            return {} unless params.is_a?(Hash)

            params.each_with_object({}) do |(key, value), sanitized|
              if SENSITIVE_KEYS.match?(key.to_s)
                sanitized[key] = "[REDACTED]"
              else
                sanitized[key] = value
              end
            end
          end

          def determine_status(result, error)
            return "error" if error
            return "rejected" if result.is_a?(Ask::Result) && (result.error? || result.blocked?)
            "success"
          end

          def determine_error(result, error)
            return error.message if error
            if result.is_a?(Ask::Result)
              return result.error.to_s if result.error?
              return result.content.to_s if result.blocked?
            end
            nil
          end

          def extract_data(result)
            return nil unless result

            if result.is_a?(Ask::Result)
              result.content.is_a?(Hash) ? result.content : nil
            elsif result.is_a?(Hash)
              result
            else
              nil
            end
          end

          def build_summary(tool_name, result, error)
            if error
              return { error: error.class.name }
            end

            if result.is_a?(Ask::Result)
              if result.error?
                return { error: "rejected: #{result.error.to_s.truncate(200)}" }
              end
              if result.blocked?
                return { error: "blocked: #{result.content.to_s.truncate(200)}" }
              end
            end

            data = extract_data(result)
            return {} unless data

            summary = {}
            summary[:rows] = data[:rows]&.length if data.key?(:rows)
            summary[:columns] = data[:columns]&.length if data.key?(:columns)
            summary[:exit_status] = data[:exit_status] if data.key?(:exit_status)
            summary[:size] = data[:size] if data.key?(:size)
            summary[:matched_lines] = data[:matched_lines] if data.key?(:matched_lines)
            summary[:results] = data[:results]&.length if data.key?(:results)
            summary[:model] = data[:name] if data.key?(:name)
            summary
          end

          def resolve_user_context
            proc = Ask::Ruby::Harness.configuration.current_user
            return nil unless proc.respond_to?(:call)

            result = proc.call
            result.is_a?(Hash) ? result : nil
          rescue StandardError
            nil
          end

          def environment_name
            Ask::Ruby::Harness.env
          end

          def table_exists?
            return false unless defined?(ActiveRecord::Base)

            # Only cache the true result — recheck if it was false
            return @table_exists if @table_exists

            @table_exists = begin
              conn = ActiveRecord::Base.connection
              conn.data_source_exists?("ask_audit_logs")
            rescue StandardError
              false
            end
          end

          def write_entry(entry)
            # Serialize JSON fields for database storage
            serialized = entry.dup
            %i[params result_summary user_context].each do |key|
              serialized[key] = ::JSON.generate(serialized[key]) if serialized[key].is_a?(Hash)
            end

            # Use raw SQL to avoid requiring a model class
            columns = serialized.keys
            values = columns.map { |col| ActiveRecord::Base.connection.quote(serialized[col]) }
            ActiveRecord::Base.connection.execute(
              "INSERT INTO ask_audit_logs (#{columns.join(', ')})
               VALUES (#{values.join(', ')})"
            )
          rescue StandardError => e
            # Silently fail — audit log should never crash the caller.
            # ::Rails avoids the bare-`Rails` constant resolving to Ask::Rails;
            # `&.` guards against Rails.logger returning nil (no app booted).
            ::Rails.logger&.warn("[ask-ruby-harness] Audit log write failed: #{e.message}") if defined?(::Rails.logger)
          end

          # Reset cached table check (useful in tests)
          public

          def reset_table_check!
            @table_exists = nil
          end
        end
      end
    end
  end
end
