# frozen_string_literal: true

require "minitest"
require "json"

module Ask
  module Ruby
    module Harness
      # Writes a machine-readable JSON summary of a minitest run.
      #
      # Registered by the ask_ruby_harness minitest plugin when the
      # ASK_TEST_JSON_PATH env var is set (see the run_tests tool). Produces
      # stable structured results — test name, klass, source file/line, status,
      # and a message head — so the harness never has to parse terminal output.
      #
      # The reporter is inert unless ASK_TEST_JSON_PATH is set, so ordinary
      # `rake test` / `bin/rails test` runs in projects that ship the harness
      # are unaffected.
      class MinitestJsonReporter < Minitest::AbstractReporter
        def initialize(path = ENV["ASK_TEST_JSON_PATH"])
          super()
          @path = path
          @results = []
        end

        def record(result)
          @results << result
        end

        def report
          return if @path.nil? || @path.to_s.empty?
          File.write(@path, JSON.pretty_generate(build_report))
        end

        # Never influences the process exit status — pass/fail is decided by
        # minitest's own summary reporter.
        def passed?
          true
        end

        private

        def build_report
          tests = @results.map { |result| test_entry(result) }
          {
            "framework" => "minitest",
            "run" => tests.size,
            "failures" => tests.count { |t| t["status"] == "failed" },
            "errors" => tests.count { |t| t["status"] == "error" },
            "skips" => tests.count { |t| t["status"] == "skipped" },
            "tests" => tests
          }
        end

        def test_entry(result)
          file, line = result.source_location
          failure = result.failure
          {
            "name" => result.name,
            "klass" => result.klass,
            "file" => file,
            "line" => line,
            "time" => result.time,
            "status" => status_of(result),
            "message" => failure ? message_of(failure) : nil
          }
        end

        def status_of(result)
          return "skipped" if result.skipped?
          return "error" if result.error?
          return "passed" if result.passed?
          "failed"
        end

        # First lines of the failure message — enough for an agent to act on
        # without dumping full backtraces into the report.
        def message_of(failure)
          failure.message.to_s.lines.first(3).map(&:strip).reject(&:empty?).join("\n")
        end
      end
    end
  end
end
