# frozen_string_literal: true

require "active_record"
require "ask/agent"
require "time"
require "yaml"

module Ask
  module Ruby
    module Harness
      class << self
        def configure
          yield configuration
        end

        def configuration
          @configuration ||= Configuration.new
        end

        # The project root the harness serves. Defaults to the current working
        # directory; framework editions set it to the framework's root at boot
        # (ask-rails-harness sets it to ::Rails.root).
        def app_root
          @app_root ||= Pathname.new(Dir.pwd)
        end

        def app_root=(path)
          @app_root = path ? Pathname.new(path) : nil
        end

        # Environment detection without Rails: RAILS_ENV, RACK_ENV, APP_ENV.
        def env
          ENV["RAILS_ENV"] || ENV["RACK_ENV"] || ENV["APP_ENV"] || "development"
        end

        def agent_session(**extra)
          # Auto-prune if configured
          cleanup! if configuration.max_session_age || configuration.max_sessions

          tools = configuration.tools.map { |t| t.is_a?(Class) ? t.new : t }
          prompt = extra.delete(:system_prompt) || configuration.system_prompt || default_system_prompt

          # Resolve environment-specific permissions and wire into agent hooks
          hooks = build_environment_hooks

          Ask::Agent::Session.new(
            model: configuration.default_model,
            max_turns: configuration.max_turns,
            system_prompt: prompt,
            tools: tools,
            state: configuration.persistence_adapter,
            hooks: hooks,
            **extra
          )
        end

        def discover_tools!
          self.configuration.tools = Ask::Tools::Shell::TOOLS.map(&:new) + harness_tools + discovered_user_tools
        end

        # Prune old sessions and audit logs based on configuration limits.
        #
        # Removes sessions older than +max_session_age+ seconds, and limits the
        # total number of sessions to +max_sessions+ (deleting the oldest first).
        # Audit log entries older than the oldest kept session are also removed.
        def cleanup!
          prune_old_sessions
          limit_session_count
        end

        # Establish a standalone ActiveRecord connection when the host hasn't
        # (Rails apps are already connected and are left untouched).
        #
        # Connection sources, in order: ASK_DATABASE_URL, config/database.yml.
        def connect_database!
          return if database_configured?

          config = ENV["ASK_DATABASE_URL"] || database_config_from_yaml
          ActiveRecord::Base.establish_connection(config) if config
        rescue StandardError => e
          warn "[ask-ruby-harness] database connect failed: #{e.message}"
        end

        # Whether a connection spec is defined. Uses the pool presence, not
        # `connected?` — ActiveRecord's connected? stays false until a
        # connection is actually checked out, while pool.with_connection
        # establishes lazily on first use.
        def database_configured?
          defined?(ActiveRecord::Base) &&
            ActiveRecord::Base.connection_handler.retrieve_connection_pool(
              ActiveRecord::Base.connection_specification_name
            )
        rescue StandardError
          false
        end

        # Config for a NAMED database. Resolution order:
        #   1. the host app's own configurations registry (Rails multi-DB —
        #      resolves credentials/ENV for us),
        #   2. config/database.yml, the current environment section's key,
        #   3. config/database.yml, the named environment section itself —
        #      "database: production" from a development-booted server
        #      resolves production's config (its "primary" pool for
        #      multi-DB apps).
        def database_config_for(name)
          name = name.to_s
          if ActiveRecord::Base.respond_to?(:configurations)
            db = ActiveRecord::Base.configurations.configs_for(env_name: env, name: name)
            return sanitize_database_config(db.configuration_hash.transform_keys(&:to_s)) if db
          end

          section = database_yaml_section
          config = section[name] if section.is_a?(Hash) && section[name].is_a?(Hash)
          return sanitize_database_config(config) if config

          yaml = database_yaml
          env_section = yaml[name] if yaml.is_a?(Hash)
          return nil unless env_section.is_a?(Hash)

          # Multi-DB apps nest pools under the env key; single-DB apps keep
          # the connection config flat under it.
          config = env_section["primary"].is_a?(Hash) ? env_section["primary"] : env_section
          sanitize_database_config(config)
        end

        private

        def build_environment_hooks
          env_mode = configuration.effective_mode
          return {} unless env_mode

          perms = Ask::Agent::Policies::Permissions.new(mode: env_mode)
          { before_tool: [perms.method(:before_tool_call)] }
        rescue ArgumentError => e
          warn "[ask-ruby-harness] Invalid environment mode: #{e.message}"
          {}
        end

        def prune_old_sessions
          age = configuration.max_session_age
          return unless age&.> 0
          return unless persistence_available?

          cutoff = age.seconds.ago
          count = 0

          configuration.persistence_adapter.list.each do |id|
            data = configuration.persistence_adapter.load(id)
            created = data&.dig(:metadata, :created_at)
            if created && Time.parse(created) < cutoff
              configuration.persistence_adapter.delete(id)
              count += 1
            end
          end

          count
        rescue StandardError
          nil
        end

        def limit_session_count
          max = configuration.max_sessions
          return unless max&.> 0
          return unless persistence_available?

          sessions = configuration.persistence_adapter.list
          excess = sessions.size - max
          return unless excess > 0

          # Delete oldest sessions first
          with_timestamps = sessions.map { |id|
            data = configuration.persistence_adapter.load(id)
            created = data&.dig(:metadata, :created_at)
            [id, created ? Time.parse(created) : Time.at(0)]
          }.sort_by(&:last)

          with_timestamps.first(excess).each do |id, _|
            configuration.persistence_adapter.delete(id)
          end

          excess
        rescue StandardError
          nil
        end

        def persistence_available?
          defined?(ActiveRecord::Base) &&
            ActiveRecord::Base.connection.data_source_exists?("ask_sessions")
        rescue StandardError
          false
        end

        def harness_tools
          HARNESS_TOOLS.map(&:new)
        end

        def discovered_user_tools
          tools = []
          files = Dir[app_root.join("app", "tools", "*.rb")]
          files.each do |f|
            require f
            klass = File.basename(f, ".rb").camelize.constantize rescue next
            tools << klass if klass < Ask::Ruby::Harness::Tool
          end
          tools
        rescue
          tools
        end

        # Config for the primary database: the `primary` section (Rails
        # multi-DB style) or the whole environment section of database.yml.
        def database_config_from_yaml
          section = database_yaml_section
          config = section["primary"].is_a?(Hash) ? section["primary"] : section
          sanitize_database_config(config)
        end

        private

        def database_yaml_section
          yaml = database_yaml || {}
          yaml[env] || yaml["development"] || {}
        end

        # Parses config/database.yml with ERB preprocessing (Rails-style) —
        # most real database.yml files embed ENV/credentials ERB, which raw
        # YAML.safe_load cannot parse. Returns nil when unreadable; the
        # callers fall back to the Rails configurations registry.
        def database_yaml
          path = app_root.join("config", "database.yml")
          return nil unless path.exist?

          require "erb"
          rendered = ERB.new(path.read).result
          YAML.safe_load(rendered, aliases: true) || {}
        rescue Psych::Exception, NameError, SyntaxError
          nil
        end

        def sanitize_database_config(config)
          return nil unless config.is_a?(Hash)

          config = config.slice(*Configuration::DATABASE_CONFIG_KEYS)
          # Resolve relative sqlite paths against app_root, like Rails does —
          # the harness may run with a different cwd than the project root.
          if config["adapter"].to_s.include?("sqlite") &&
             config["database"] && !config["database"].start_with?("/", ":")
            config["database"] = app_root.join(config["database"]).to_s
          end
          config.presence
        end

        def default_system_prompt
          <<~PROMPT
            You are a Ruby software engineer.
            You have direct access to the project's code, database, and runtime.
            Use your tools to inspect and modify the codebase.
            Once you have enough information, stop calling tools and give your answer.
          PROMPT
        end
      end
    end
  end
end

require_relative "harness/version"
require_relative "harness/configuration"
require_relative "harness/audit_log"
require_relative "harness/environment_permissions"
require_relative "harness/tool"
require_relative "harness/tools/run_command"
require_relative "harness/tools/query_database"
require_relative "harness/tools/read_model"
require_relative "harness/tools/read_log"
require_relative "harness/tools/schema_graph"
require_relative "harness/tools/run_tests"
require_relative "harness/tools/dev_url"

# Define after all tool files are loaded so the constants resolve
Ask::Ruby::Harness::HARNESS_TOOLS = [
  Ask::Ruby::Harness::Tools::RunCommand, Ask::Ruby::Harness::Tools::QueryDatabase,
  Ask::Ruby::Harness::Tools::ReadModel, Ask::Ruby::Harness::Tools::ReadLog,
  Ask::Ruby::Harness::Tools::SchemaGraph, Ask::Ruby::Harness::Tools::RunTests,
  Ask::Ruby::Harness::Tools::DevUrl
].freeze
