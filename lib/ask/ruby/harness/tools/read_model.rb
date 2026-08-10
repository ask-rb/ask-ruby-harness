# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module Ask
  module Ruby
    module Harness
      module Tools
        class ReadModel < Ask::Ruby::Harness::Tool
          description "Inspect an ActiveRecord model — columns, associations, validations, " \
                       "scopes, and indexes. Returns structured data the agent can act on."

          param :name,   type: :string, desc: "Model class name (e.g. 'User', 'Blog::Post')", required: true
          param :detail, type: :string, desc: "Which details: 'all' (default), 'columns', 'associations', 'validations', 'scopes'", required: false

          def execute(name:, detail: "all")
            klass = safe_constantize(name)
            return Ask::Result.failure("Model '#{name}' not found or is not an ActiveRecord model.") unless klass

            result = { name: klass.name, table_name: klass.table_name }

            result[:primary_key] = klass.primary_key if klass.respond_to?(:primary_key)

            if %w[all columns].include?(detail)
              result[:columns] = klass.columns.map { |c|
                entry = { name: c.name, type: c.type, null: c.null, default: c.default }
                entry[:primary_key] = true if c.name == klass.primary_key
                entry
              }
            end

            if %w[all associations].include?(detail)
              result[:associations] = klass.reflect_on_all_associations.group_by(&:macro).transform_values { |refs|
                refs.map { |a|
                  entry = { name: a.name, class_name: a.class_name }
                  entry[:through] = a.options[:through] if a.options[:through]
                  entry[:source] = a.options[:source] if a.options[:source]
                  entry[:foreign_key] = a.foreign_key if a.respond_to?(:foreign_key)
                  entry
                }
              }
            end

            if %w[all scopes].include?(detail) && klass.respond_to?(:all)
              result[:scopes] = klass.methods(false)
                .reject { |m| m.to_s.end_with?("=", "!", "?") || %i[new allocate inspect to_s].include?(m) }
                .map(&:to_s).sort
            end

            if %w[all validations].include?(detail)
              result[:validators] = klass.validators.map { |v|
                {
                  attribute: v.attributes.first&.to_s,
                  kind: v.kind,
                  options: v.options.reject { |k, _| k == :if }
                }
              }.reject { |v| v[:attribute].nil? }
            end

            result
          end

          private

          def safe_constantize(name)
            klass = name.safe_constantize
            return nil unless klass
            return nil unless klass < ActiveRecord::Base
            klass
          rescue
            nil
          end
        end
      end
    end
  end
end
