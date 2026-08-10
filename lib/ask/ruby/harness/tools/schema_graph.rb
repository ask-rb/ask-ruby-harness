# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      module Tools
        class SchemaGraph < Ask::Ruby::Harness::Tool
          description "Return the full application schema graph — all models, tables, columns with types, " \
                       "associations (belongs_to, has_many, has_one, HABTM, through), validations, indexes, " \
                       "and polymorphic relationships. One call gives the agent a complete mental model " \
                       "of the application's data layer."

          param :detail, type: :string, desc: "Detail level: 'all' (default), 'models', 'associations', 'tables'", required: false

          TABLE_EXCLUSIONS = %w[schema_migrations ar_internal_metadata].freeze

          def execute(detail: "all")
            models = discover_ar_models

            result = {
              summary: {
                model_count: models.size,
                table_count: models.map { |m| m.table_name }.uniq.size,
                association_count: models.sum { |m| m.reflect_on_all_associations.size }
              },
              models: %w[all models].include?(detail) ? build_model_details(models, detail) : nil,
              associations: %w[all associations].include?(detail) ? build_association_graph(models) : nil,
              tables: %w[all tables].include?(detail) ? build_table_details(detail) : nil
            }

            result
          end

          private

          def discover_ar_models
            # Eager-load the host app's models when it's a full framework app
            # (Rails); in a plain Ruby project the models are loaded by
            # whatever loaded them.
            if defined?(::Rails::Application) && ::Rails.application
              ::Rails.application.eager_load! rescue nil
            end
            ActiveRecord::Base.descendants.reject do |klass|
              klass.abstract_class? ||
              klass.name.nil? ||
              TABLE_EXCLUSIONS.include?(klass.table_name) ||
              klass.name.start_with?("ActiveRecord::", "ActiveStorage::", "ActionText::")
            end.sort_by(&:name)
          rescue StandardError
            []
          end

          def build_model_details(models, detail)
            models.filter_map do |klass|
              name = klass.name rescue nil
              next nil unless name

              entry = {
                name: name,
                table_name: klass.table_name,
                primary_key: safe_primary_key(klass)
              }

              if klass.respond_to?(:columns)
                entry[:columns] = safe_columns(klass)
              end

              if klass.respond_to?(:reflect_on_all_associations)
                entry[:associations] = klass.reflect_on_all_associations.group_by(&:macro).transform_values { |refs|
                  refs.map { |a|
                    assoc = { name: a.name, class_name: a.class_name }
                    assoc[:through] = a.options[:through] if a.options[:through]
                    assoc[:source] = a.options[:source] if a.options[:source]
                    assoc[:foreign_key] = a.foreign_key
                    assoc[:polymorphic] = true if a.polymorphic?
                    assoc[:as] = a.options[:as] if a.options[:as]
                    assoc[:dependent] = a.options[:dependent] if a.options[:dependent]
                    assoc
                  }
                }
              end

              if klass.respond_to?(:validators)
                entry[:validators] = klass.validators.map { |v|
                  {
                    attribute: v.attributes.first&.to_s,
                    kind: v.kind,
                    options: v.options.reject { |k, _| k == :if }
                  }
                }.reject { |v| v[:attribute].nil? }
              end

              entry
            end
          end

          def build_association_graph(models)
            edges = []

            models.each do |klass|
              klass.reflect_on_all_associations.each do |a|
                next if a.macro == :has_many && a.options[:through]  # Skip through associations (derived)

                target_model = find_model_for_association(models, a)
                next unless target_model

                edges << {
                  from: klass.name,
                  to: target_model.name,
                  type: a.macro,
                  via: a.name,
                  foreign_key: a.foreign_key,
                  polymorphic: a.polymorphic? || false
                }
              end
            end

            edges
          end

          def find_model_for_association(models, association)
            class_name = association.class_name
            # Try exact match first, then match by class name suffix (handles namespace issues)
            models.find { |m| m.name == class_name } ||
              models.find { |m| m.name.end_with?("::#{class_name}") } ||
              models.find { |m| class_name.end_with?("::#{m.name}") }
          end

          def build_table_details(detail)
            models = discover_ar_models
            tables = {}

            models.each do |klass|
              table = klass.table_name
              next if TABLE_EXCLUSIONS.include?(table)

              tables[table] = {
                model: klass.name,
                columns: safe_columns(klass),
                indexes: fetch_indexes_for(table)
              }
            end

            tables
          end

          def safe_primary_key(klass)
            klass.primary_key
          rescue StandardError
            nil
          end

          def safe_columns(klass)
            klass.columns.map { |c|
              col = { name: c.name, type: c.type, null: c.null }
              col[:default] = c.default unless c.default.nil?
              col[:primary_key] = true if c.name == klass.primary_key
              col
            }
          rescue StandardError
            []
          end

          def fetch_indexes_for(table_name)
            ActiveRecord::Base.connection.indexes(table_name).map do |idx|
              {
                name: idx.name,
                columns: idx.columns,
                unique: idx.unique
              }
            end
          rescue StandardError
            []
          end
        end
      end
    end
  end
end
