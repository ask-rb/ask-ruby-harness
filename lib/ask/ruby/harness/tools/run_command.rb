# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      module Tools
        class RunCommand < Ask::Ruby::Harness::Tool
          description "Run a shell command in the project root directory."
          param :command, type: :string, desc: "Shell command to run", required: true

          def execute(command:)
            check_result = check_command_allowed(command)
            return check_result if check_result

            output = `cd #{app_root} && #{command} 2>&1`
            Ask::Result.ok(
              data: { output: output, exit_status: $?.exitstatus },
              metadata: { exit_status: $?.exitstatus }
            )
          end

          private

          def check_command_allowed(command)
            config = Ask::Ruby::Harness.configuration

            # Use per-environment rules if configured, fall back to global
            denied = config.effective_denied_commands
            allowed = config.effective_allowed_commands

            # 1. Check denied commands first (takes precedence)
            if denied
              denied.each do |pattern|
                if command.match?(pattern)
                  return Ask::Result.error(
                    message: "Command blocked by deny rule: #{pattern.inspect}"
                  )
                end
              end
            end

            # 2. Check allowed commands (if configured)
            if allowed
              matches = allowed.any? { |pattern| command.match?(pattern) }
              unless matches
                allowed_desc = allowed.map(&:inspect).join(", ")
                return Ask::Result.error(
                  message: "Command blocked: does not match any allowed pattern (#{allowed_desc})"
                )
              end
            end

            # 3. No restrictions configured — allow
            nil
          end
        end
      end
    end
  end
end
