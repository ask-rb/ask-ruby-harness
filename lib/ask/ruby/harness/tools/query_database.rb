# frozen_string_literal: true

require "time"
require "uri"

module Ask
  module Ruby
    module Harness
      module Tools
        class QueryDatabase < Ask::Ruby::Harness::Tool
          description "Run a read-only SQL query against the application database. " \
                       "Returns columns and rows. Only SELECT queries are allowed in production. " \
                       "Multi-database apps can target a named database (a config/database.yml " \
                       "key or a full connection URL) with the database param."

          param :sql,   type: :string, desc: "SQL query (SELECT only in production)", required: true
          param :limit, type: :integer, desc: "Max rows to return (default 50)", required: false
          param :database, type: :string, desc: "Named database from config/database.yml or a full connection URL (default: primary)", required: false

          WRITE_STATEMENTS = /\A\s*(INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE)\b/i
          URL_PATTERN = %r{\A[a-z][a-z0-9+]*://}

          def execute(sql:, limit: 50, database: nil)
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

            pool = resolve_pool(database)
            return pool if pool.is_a?(Ask::Result)

            result = pool.with_connection do |conn|
              limited_sql = sql.match?(/\bLIMIT\b/i) ? sql : "#{sql.chomp(';')} LIMIT #{limit.to_i}"
              query_result = conn.exec_query(limited_sql)
              columns = query_result.columns
              rows = query_result.rows.first(limit.to_i).map { |row| build_row(row, columns) }
              {
                columns: columns,
                rows: rows,
                count: rows.size,
                truncated: query_result.rows.size > limit.to_i
              }
            end
            result.merge(database: resolved_database_name(database))
          rescue ActiveRecord::StatementInvalid => e
            Ask::Result.failure("SQL error: #{e.message}")
          rescue ActiveRecord::ConnectionNotEstablished => e
            Ask::Result.failure(
              "Database not connected: #{e.message}. Set ASK_DATABASE_URL or provide a config/database.yml."
            )
          end

          private

          # Resolve the connection pool for the target database:
          #   - nil/"primary" → the default pool (connecting standalone when needed)
          #   - a URL        → a pool established from that URL
          #   - a name       → an existing pool (Rails multi-DB), else a pool
          #                    established from config/database.yml
          def resolve_pool(database)
            if database.nil? || database == "primary"
              unless Ask::Ruby::Harness.database_configured?
                Ask::Ruby::Harness.connect_database!
              end
              unless Ask::Ruby::Harness.database_configured?
                return Ask::Result.failure(
                  "Database not connected. Set ASK_DATABASE_URL or provide a config/database.yml."
                )
              end
              return ActiveRecord::Base.connection_pool
            end

            name = database.to_s
            pool = ActiveRecord::Base.connection_handler.retrieve_connection_pool(name)
            return pool if pool

            config = url_config(database) || Ask::Ruby::Harness.database_config_for(name)
            unless config
              return Ask::Result.failure(
                "Database '#{database}' not found. Add it to config/database.yml or pass a full connection URL."
              )
            end

            owner = name.match?(URL_PATTERN) ? "ask_url_#{name.hash.abs}" : name.to_sym
            ActiveRecord::Base.connection_handler.establish_connection(config, owner_name: owner)
            ActiveRecord::Base.connection_handler.retrieve_connection_pool(owner.to_s) ||
              Ask::Result.failure("Could not connect to database '#{database}'.")
          end

          def url_config(database)
            database if database.to_s.match?(URL_PATTERN)
          end

          # What to report back as `database`: the config key as passed, or
          # the database name parsed from a URL (never the full URL — it may
          # carry credentials).
          def resolved_database_name(database)
            return "primary" if database.nil? || database == "primary"
            return database unless database.to_s.match?(URL_PATTERN)

            uri = URI.parse(database)
            name = uri.path.to_s.delete_prefix("/")
            name = File.basename(name) if name.include?("/")
            name.empty? ? uri.host.to_s : name
          rescue URI::InvalidURIError
            database
          end

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
