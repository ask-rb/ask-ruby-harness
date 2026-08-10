# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "rbconfig"
require "open3"

class MinitestJsonReporterTest < Minitest::Test
  # A result quacking like Minitest::Result — enough for the reporter.
  FakeResult = Struct.new(:name, :klass, :source_location, :time, :failures, keyword_init: true) do
    def failure
      failures.first
    end

    def skipped?
      Minitest::Skip === failure
    end

    def error?
      failures.any? { |f| Minitest::UnexpectedError === f }
    end

    def passed?
      failure.nil?
    end
  end

  def setup
    @json_path = File.join(Dir.mktmpdir, "report.json")
  end

  def test_report_writes_counts_and_test_entries
    reporter = Ask::Ruby::Harness::MinitestJsonReporter.new(@json_path)
    reporter.record(passing_result)
    reporter.record(failing_result)
    reporter.record(erroring_result)
    reporter.record(skipping_result)
    reporter.report

    payload = JSON.parse(File.read(@json_path))
    assert_equal "minitest", payload["framework"]
    assert_equal 4, payload["run"]
    assert_equal 1, payload["failures"]
    assert_equal 1, payload["errors"]
    assert_equal 1, payload["skips"]
    assert_equal 4, payload["tests"].size

    failed = payload["tests"].find { |t| t["status"] == "failed" }
    assert_equal "test_asserts_equal", failed["name"]
    assert_equal "WidgetTest", failed["klass"]
    assert_equal "test/widget_test.rb", failed["file"]
    assert_equal 12, failed["line"]
    assert_includes failed["message"], "Expected 2 == 1"
  end

  def test_report_writes_nothing_without_path
    reporter = Ask::Ruby::Harness::MinitestJsonReporter.new(nil)
    reporter.record(passing_result)
    reporter.report

    refute File.exist?(File.join(@json_path)), "no JSON should be written without a path"
  end

  def test_passed_reporter_never_flips_exit_status
    reporter = Ask::Ruby::Harness::MinitestJsonReporter.new(nil)
    assert reporter.passed?, "reporters must not change the process exit status"
  end

  # --- integration: the real minitest plugin path --------------------------
  #
  # Runs a scratch minitest suite under this gem's own bundle (bundle exec),
  # so minitest auto-discovers lib/minitest/ask_ruby_harness_plugin.rb and
  # the plugin registers the reporter via ASK_TEST_JSON_PATH — exactly what
  # happens when a project runs `rake test` through the harness.

  def test_plugin_discovers_and_writes_json_in_real_minitest_run
    Dir.mktmpdir do |dir|
      suite = File.join(dir, "scratch_test.rb")
      File.write(suite, <<~RUBY)
        require "minitest/autorun"

        class ScratchTest < Minitest::Test
          def test_passes
            assert true
          end

          def test_fails
            assert_equal 1, 2
          end

          def test_errors
            raise "boom"
          end

          def test_skips
            skip "later"
          end
        end
      RUBY

      json = File.join(dir, "report.json")
      command = ["bundle", "exec", RbConfig.ruby, "-I", dir, suite]
      stdout, stderr, status = with_bundle_env do
        Open3.capture3({ "ASK_TEST_JSON_PATH" => json }, *command)
      end

      assert status.exited?, "scratch suite must run (stderr: #{stderr[0, 200]})"
      payload = JSON.parse(File.read(json))

      assert_equal "minitest", payload["framework"]
      assert_equal 4, payload["run"]
      assert_equal 1, payload["failures"]
      assert_equal 1, payload["errors"]
      assert_equal 1, payload["skips"]

      by_name = payload["tests"].to_h { |t| [t["name"], t] }
      assert_equal "passed", by_name["test_passes"]["status"]
      assert_equal "failed", by_name["test_fails"]["status"]
      assert_includes by_name["test_fails"]["message"], "Expected"
      assert_equal "error", by_name["test_errors"]["status"]
      assert_equal "skipped", by_name["test_skips"]["status"]
      assert_equal suite, by_name["test_fails"]["file"]
      assert_equal 8, by_name["test_fails"]["line"]
    end
  end

  private

  def passing_result
    FakeResult.new(name: "test_works", klass: "WidgetTest",
                   source_location: ["test/widget_test.rb", 4], time: 0.01, failures: [])
  end

  def failing_result
    FakeResult.new(name: "test_asserts_equal", klass: "WidgetTest",
                   source_location: ["test/widget_test.rb", 12], time: 0.02,
                   failures: [Minitest::Assertion.new("Expected 2 == 1")])
  end

  def erroring_result
    FakeResult.new(name: "test_raises", klass: "WidgetTest",
                   source_location: ["test/widget_test.rb", 17], time: 0.03,
                   failures: [Minitest::UnexpectedError.new(RuntimeError.new("boom"))])
  end

  def skipping_result
    FakeResult.new(name: "test_skips", klass: "WidgetTest",
                   source_location: ["test/widget_test.rb", 22], time: 0.0,
                   failures: [Minitest::Skip.new("later")])
  end

  def with_bundle_env(&block)
    # A fresh `bundle exec` inside the suite requires stripping Bundler's
    # in-process environment so the child resolves the gem's own Gemfile.
    Bundler.with_unbundled_env do
      Dir.chdir(File.expand_path("..", __dir__)) { yield }
    end
  end
end
