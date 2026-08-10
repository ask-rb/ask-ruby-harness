# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      class Configuration
        # Keys accepted when building a standalone connection from
        # config/database.yml (unknown keys would fail AR's config validation).
        DATABASE_CONFIG_KEYS = %w[adapter database host port username password url encoding pool].freeze

        attr_accessor :default_model, :max_turns, :system_prompt,
                      :tool_concurrency, :persistence_adapter, :tools,
                      :current_user, :allowed_commands, :denied_commands,
                      :max_session_age, :max_sessions

        # @return [Hash{Symbol => EnvironmentPermissions}] per-environment permission rules
        attr_reader :environments

        def initialize
          @default_model = "gpt-4o"
          @max_turns = 25
          @system_prompt = nil
          @tool_concurrency = 5
          @persistence_adapter = nil
          @tools = []
          @current_user = nil
          @allowed_commands = nil
          @denied_commands = nil
          @max_session_age = nil
          @max_sessions = nil
          @environments = {}
        end

        # Configure permissions for a specific environment.
        #
        #   config.environment :production do |env|
        #     env.mode = :read_only
        #     env.allowed_commands = [/^rails routes/]
        #     env.denied_commands = [/rm/, /dropdb/]
        #   end
        #
        # @param name [Symbol, String] environment name (:production, :development, :staging, etc.)
        def environment(name)
          env = EnvironmentPermissions.new
          yield env
          @environments[name.to_sym] = env
        end

        # Resolved allowed commands for the current environment.
        # Falls back to the global +allowed_commands+ if no per-env config.
        #
        # @return [Array<Regexp>, nil]
        def effective_allowed_commands
          env = @environments[Ask::Ruby::Harness.env.to_sym]
          env&.allowed_commands || @allowed_commands
        end

        # Resolved denied commands for the current environment.
        # Falls back to the global +denied_commands+ if no per-env config.
        #
        # @return [Array<Regexp>, nil]
        def effective_denied_commands
          env = @environments[Ask::Ruby::Harness.env.to_sym]
          env&.denied_commands || @denied_commands
        end

        # Resolved access mode for the current environment.
        #
        # @return [Symbol, nil] +:full_access+, +:read_only+, +:ask_before_changes+, or nil
        def effective_mode
          env = @environments[Ask::Ruby::Harness.env.to_sym]
          env&.mode || nil
        end
      end
    end
  end
end
