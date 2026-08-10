# frozen_string_literal: true

require "time"

module Ask
  module Ruby
    module Harness
      module Tools
        class QueryDatabase < Ask::Ruby::Harness::Tool
          description "Run a read-only SQL query against the application database. " \
                       "Returns columns and rows. Only SELECT queries are allowed in production."

          param :sql,   type: :string, desc: "SQL query (SELECT only in production)", required: true
          param :limit, type: :integer, desc: "Max rows to return (default 50)", required: false

          WRITE_STATEMENTS = /\A\s*(INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE)\b/i

          def execute(sql:, limit: 50)
            sql = sql.strip

            if WRITE_STATEMENTS.match?(sql)
              return Ask::Result.failure(
                "Only SELECT queries are allowed. Write statements (#{sql.match(WRITE_STATEMENTS)[1]}) are rejected in all environments."
              )
            end

            if Ask::Ruby::Harness.env == "production" && !sql.match?(/\A\s*SELECT\b/i)
              return Ask::Result.failure(
                "Only SELECT queries are allowed in the production environment."
              )
            end

            unless Ask::Ruby::Harness.database_configured?
              Ask::Ruby::Harness.connect_database!
            end
            unless Ask::Ruby::Harness.database_configured?
              return Ask::Result.failure(
                "Database not connected. Set ASK_DATABASE_URL or provide a config/database.yml."
              )
            end

            pool = ActiveRecord::Base.connection_pool
            pool.with_connection do |conn|
              limited_sql = sql.match?(/\bLIMIT\b/i) ? sql : "#{sql.chomp(';')} LIMIT #{limit.to_i}"
              result = conn.exec_query(limited_sql)
              columns = result.columns
              rows = result.rows.first(limit.to_i).map { |row| build_row(row, columns) }
              {
                columns: columns,
                rows: rows,
                count: rows.size,
                truncated: result.rows.size > limit.to_i
              }
            end
          rescue ActiveRecord::StatementInvalid => e
            Ask::Result.failure("SQL error: #{e.message}")
          rescue ActiveRecord::ConnectionNotEstablished => e
            Ask::Result.failure(
              "Database not connected: #{e.message}. Set ASK_DATABASE_URL or config/database.yml."
            )
          end

          private

          def build_row(row, columns)
            columns.each_with_index.each_with_object({}) do |(col, i), hash|
              value = row[i]
              hash[col] = sanitize_value(value)
            end
          end

          def sanitize_value(value)
            return "[BINARY DATA]" if binary_value?(value)
            return value.iso8601 if value.respond_to?(:iso8601)
            value
          end

          def binary_value?(value)
            value.is_a?(String) && value.encoding == Encoding::ASCII_8BIT && value.bytesize > 0
          rescue
            false
          end
        end
      end
    end
  end
end
