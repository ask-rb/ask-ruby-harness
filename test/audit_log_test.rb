# frozen_string_literal: true

require_relative "test_helper"
require "active_record"
require "tmpdir"

class AuditLogTest < Minitest::Test
  def setup
    @original_current_user = Ask::Ruby::Harness.configuration.current_user
    ensure_test_db
    Ask::Ruby::Harness::AuditLog.reset_table_check!
  end

  def teardown
    Ask::Ruby::Harness.configuration.current_user = @original_current_user
    clear_logs
  end

  def test_logs_a_successful_tool_call
    result = { rows: [{ "id" => 1 }], columns: %w[id] }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "session-1",
      tool_name: "query_database",
      params: { sql: "SELECT * FROM users", limit: 50 },
      result: result,
      duration_ms: 23
    )

    assert_equal "session-1", entry[:session_id]
    assert_equal "query_database", entry[:tool_name]
    assert_equal "success", entry[:status]
    assert_equal 23, entry[:duration_ms]
    assert_equal "development", entry[:environment]
  end

  def test_logs_a_failed_tool_call
    result = Ask::Result.failure("Write statements not allowed")

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "session-1",
      tool_name: "query_database",
      params: { sql: "DROP TABLE users" },
      result: result,
      duration_ms: 5
    )

    assert_equal "rejected", entry[:status]
    assert_includes entry[:error_message], "Write statements not allowed"
  end

  def test_logs_an_exception
    error = RuntimeError.new("Connection timeout")

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "session-1",
      tool_name: "run_command",
      params: { command: "sleep 60" },
      error: error,
      duration_ms: 30_001
    )

    assert_equal "error", entry[:status]
    assert_equal "Connection timeout", entry[:error_message]
  end

  def test_redacts_sensitive_params
    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "session-1",
      tool_name: "run_command",
      params: { command: "echo hello", password: "secret123", api_key: "sk-xxx" },
      duration_ms: 10
    )

    assert_equal "echo hello", entry[:params][:command]
    assert_equal "[REDACTED]", entry[:params][:password]
    assert_equal "[REDACTED]", entry[:params][:api_key]
  end

  def test_builds_query_summary
    result = { rows: [{ "id" => 1 }, { "id" => 2 }], columns: %w[id name email] }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "query_database",
      params: { sql: "SELECT * FROM users" }, result: result, duration_ms: 10
    )

    assert_equal 2, entry[:result_summary][:rows]
    assert_equal 3, entry[:result_summary][:columns]
  end

  def test_builds_command_summary
    result = { output: "done", exit_status: 0 }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "bundle exec rake routes" }, result: result, duration_ms: 120
    )

    assert_equal 0, entry[:result_summary][:exit_status]
  end

  def test_builds_model_summary
    result = { name: "User", table_name: "users", columns: [] }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "read_model",
      params: { name: "User" }, result: result, duration_ms: 4
    )

    assert_equal "User", entry[:result_summary][:model]
  end

  def test_builds_read_log_summary
    result = { lines: ["error"], total_lines: 100, matched_lines: 1 }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "read_log",
      params: { lines: 50, level: "ERROR" }, result: result, duration_ms: 8
    )

    assert_equal 1, entry[:result_summary][:matched_lines]
  end

  def test_includes_user_context_when_configured
    Ask::Ruby::Harness.configuration.current_user = -> { { id: 42, email: "admin@test.com" } }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "echo hi" }, duration_ms: 3
    )

    assert_equal 42, entry[:user_context][:id]
    assert_equal "admin@test.com", entry[:user_context][:email]
  end

  def test_user_context_is_nil_when_not_configured
    Ask::Ruby::Harness.configuration.current_user = nil

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "echo hi" }, duration_ms: 3
    )

    assert_nil entry[:user_context]
  end

  def test_user_context_is_nil_when_proc_returns_non_hash
    Ask::Ruby::Harness.configuration.current_user = -> { "just a string" }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "echo hi" }, duration_ms: 3
    )

    assert_nil entry[:user_context]
  end

  def test_user_context_gracefully_handles_proc_error
    Ask::Ruby::Harness.configuration.current_user = -> { raise "oops" }

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "echo hi" }, duration_ms: 3
    )

    assert_nil entry[:user_context]
  end

  def test_fires_active_support_notification
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("audit_log.ask_ruby_harness") do |_name, _start, _finish, _id, payload|
      events << payload
    end

    Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "echo hi" }, duration_ms: 5
    )

    assert_equal 1, events.length
    assert_equal "run_command", events.first[:tool_name]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def test_writes_to_database
    Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "run_command",
      params: { command: "echo hi" }, duration_ms: 5
    )

    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) AS cnt FROM ask_audit_logs").first["cnt"]
    assert_equal 1, count
  end

  def test_logs_are_append_only
    3.times do |i|
      Ask::Ruby::Harness::AuditLog.log(
        session_id: "s1", tool_name: "run_command",
        params: { command: "echo hi" }, duration_ms: i
      )
    end

    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) AS cnt FROM ask_audit_logs").first["cnt"]
    assert_equal 3, count
  end

  def test_parses_rejected_result_error_in_summary
    result = Ask::Result.failure("Write statements not allowed in production")

    entry = Ask::Ruby::Harness::AuditLog.log(
      session_id: "s1", tool_name: "query_database",
      params: { sql: "DROP TABLE users" }, result: result, duration_ms: 2
    )

    assert_equal "rejected", entry[:status]
    assert_includes entry[:result_summary][:error], "Write statements not allowed"
  end

  private

  def ensure_test_db
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    create_audit_logs_table unless ActiveRecord::Base.connection.table_exists?("ask_audit_logs")
  rescue StandardError
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    create_audit_logs_table
  end

  def create_audit_logs_table
    ActiveRecord::Base.connection.create_table(:ask_audit_logs, force: true) do |t|
      t.string :session_id, null: false
      t.string :tool_name, null: false
      t.text :params
      t.text :result_summary
      t.string :status, null: false, default: "success"
      t.text :error_message
      t.integer :duration_ms
      t.text :user_context
      t.string :environment
      t.datetime :recorded_at, null: false
      t.timestamps
    end
  end

  def clear_logs
    ActiveRecord::Base.connection.execute("DELETE FROM ask_audit_logs") if ActiveRecord::Base.connection.table_exists?("ask_audit_logs")
  rescue StandardError
    nil
  end
end
