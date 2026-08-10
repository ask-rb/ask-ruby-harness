# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      # Per-environment permission rules for agent tool access.
      #
      # Configure within Ask::Ruby::Harness.configure block:
      #
      #   Ask::Ruby::Harness.configure do |config|
      #     config.environment :production do |env|
      #       env.mode = :read_only
      #       env.allowed_commands = [/^rails routes/, /^rails log/]
      #       env.denied_commands = [/rm/, /dropdb/]
      #     end
      #
      #     config.environment :development do |env|
      #       env.mode = :full_access
      #     end
      #   end
      #
      class EnvironmentPermissions
        # @return [Symbol, nil] Access mode for ask-agent's Permissions extension
        #   (:full_access, :read_only, :ask_before_changes)
        attr_accessor :mode

        # @return [Array<Regexp>, nil] Allowed command patterns for RunCommand
        attr_accessor :allowed_commands

        # @return [Array<Regexp>, nil] Denied command patterns for RunCommand (takes precedence)
        attr_accessor :denied_commands

        def initialize
          @mode = nil
          @allowed_commands = nil
          @denied_commands = nil
        end
      end
    end
  end
end
