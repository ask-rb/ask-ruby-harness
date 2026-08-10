# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class ToolsTest < Minitest::Test
  def setup
    @run_command = Ask::Ruby::Harness::Tools::RunCommand.new
    @query_database = Ask::Ruby::Harness::Tools::QueryDatabase.new
    @read_model = Ask::Ruby::Harness::Tools::ReadModel.new
    @read_log = Ask::Ruby::Harness::Tools::ReadLog.new
  end

  def test_run_command_defines_correct_params
    assert_equal "run_command", @run_command.name
    assert @run_command.parameters.key?(:command)
  end

  def test_run_command_blocked_by_denied_pattern
    original = Ask::Ruby::Harness.configuration.denied_commands
    Ask::Ruby::Harness.configuration.denied_commands = [/rm -rf/]
    result = @run_command.call(command: "rm -rf /tmp/foo")
    assert_instance_of Ask::Result, result
    assert result.error?
  ensure
    Ask::Ruby::Harness.configuration.denied_commands = original
  end

  def test_run_command_allowed_by_allowlist
    original = Ask::Ruby::Harness.configuration.allowed_commands
    Ask::Ruby::Harness.configuration.allowed_commands = [/^echo /]
    result = @run_command.call(command: "echo hello")
    assert_instance_of Ask::Result, result
    assert result.ok?
    assert_includes result.output[:output], "hello"
  ensure
    Ask::Ruby::Harness.configuration.allowed_commands = original
  end

  def test_run_command_blocked_when_not_in_allowlist
    original = Ask::Ruby::Harness.configuration.allowed_commands
    Ask::Ruby::Harness.configuration.allowed_commands = [/^echo /]
    result = @run_command.call(command: "ls /tmp")
    assert_instance_of Ask::Result, result
    assert result.error?
  ensure
    Ask::Ruby::Harness.configuration.allowed_commands = original
  end

  def test_run_command_deny_takes_precedence_over_allow
    original_allowed = Ask::Ruby::Harness.configuration.allowed_commands
    original_denied = Ask::Ruby::Harness.configuration.denied_commands
    Ask::Ruby::Harness.configuration.allowed_commands = [/rm -rf/]
    Ask::Ruby::Harness.configuration.denied_commands = [/rm -rf/]
    result = @run_command.call(command: "rm -rf /tmp/foo")
    assert result.error?
  ensure
    Ask::Ruby::Harness.configuration.allowed_commands = original_allowed
    Ask::Ruby::Harness.configuration.denied_commands = original_denied
  end

  def test_run_command_unchanged_when_no_rules
    result = @run_command.call(command: "echo unchanged")
    assert_instance_of Ask::Result, result
    assert result.ok?
  end

  # --- QueryDatabase tests ---

  def test_query_database_defines_correct_params
    assert_equal "query_database", @query_database.name
    assert @query_database.parameters.key?(:sql)
    assert @query_database.parameters.key?(:limit)
  end

  def test_query_database_rejects_insert
    result = @query_database.call(sql: "INSERT INTO users (name) VALUES ('test')")
    assert_instance_of Ask::Result, result
    assert result.error?
  end

  def test_query_database_rejects_write_statements
    %w[UPDATE DELETE DROP TRUNCATE ALTER CREATE GRANT REVOKE].each do |stmt|
      result = @query_database.call(sql: "#{stmt} TABLE users")
      assert result.error?, "#{stmt} should be rejected"
    end
  end

  def test_query_database_rejects_non_select_in_production
    with_env("APP_ENV" => "production") do
      result = @query_database.call(sql: "WITH x AS (SELECT 1) SELECT * FROM x")
      assert result.error?
    end
  end

  def test_query_database_select_with_live_db
    with_test_db do |_db|
      result = @query_database.call(sql: "SELECT * FROM test_items ORDER BY value ASC")
      assert_instance_of Hash, result, "Expected Hash but got #{result.class}"
      assert_equal %w[id name value], result[:columns]
      assert_equal 5, result[:count]
      assert_equal "item_0", result[:rows][0]["name"]
      assert_equal 40, result[:rows][-1]["value"]
    end
  end

  def test_query_database_auto_appends_limit
    with_test_db do |_db|
      result = @query_database.call(sql: "SELECT * FROM test_items", limit: 2)
      assert_instance_of Hash, result
      assert_equal 2, result[:count]
      refute result[:truncated], "Should not be truncated with limit >= count"
    end
  end

  def test_query_database_empty_result
    with_test_db do |_db|
      result = @query_database.call(sql: "SELECT * FROM test_items WHERE value < 0")
      assert_instance_of Hash, result
      assert_equal 0, result[:count]
      assert_equal [], result[:rows]
    end
  end

  def test_query_database_malformed_sql
    with_test_db do |_db|
      result = @query_database.call(sql: "SELEC * FRM test_items")
      assert_instance_of Ask::Result, result
      assert result.error?
    end
  end

  def test_query_database_reports_unconnected_database
    # No connection spec defined and nothing to connect with → clean failure.
    Ask::Ruby::Harness.stubs(:database_configured?).returns(false)
    Ask::Ruby::Harness.stubs(:connect_database!)
    result = @query_database.call(sql: "SELECT 1")
    assert_instance_of Ask::Result, result
    assert result.error?
    assert_includes result.error.to_s, "Database not connected"
  end

  # --- ReadModel tests ---

  def test_read_model_defines_correct_params
    assert_equal "read_model", @read_model.name
    assert @read_model.parameters.key?(:name)
    assert @read_model.parameters.key?(:detail)
  end

  def test_read_model_not_found
    result = @read_model.call(name: "NonExistentModel12345")
    assert_instance_of Ask::Result, result
    assert result.error?
  end

  def test_read_model_not_active_record
    result = @read_model.call(name: "String")
    assert_instance_of Ask::Result, result
    assert result.error?
  end

  def test_read_model_returns_columns
    with_test_model do |model_name|
      result = @read_model.call(name: model_name)
      assert_instance_of Hash, result
      assert result.key?(:columns), "read_model should return columns"
      assert result[:columns].any? { |c| c[:name] == "name" }, "should include name column"
      assert result[:columns].any? { |c| c[:name] == "email" }, "should include email column"
    end
  end

  def test_read_model_returns_table_name
    with_test_model do |model_name|
      result = @read_model.call(name: model_name)
      assert_instance_of Hash, result
      assert result.key?(:table_name)
      assert result[:table_name].present?
    end
  end

  def test_read_model_returns_primary_key
    with_test_model do |model_name|
      result = @read_model.call(name: model_name)
      assert_instance_of Hash, result
      assert_equal "id", result[:primary_key]
    end
  end

  def test_read_model_detail_columns_only
    with_test_model do |model_name|
      result = @read_model.call(name: model_name, detail: "columns")
      assert_instance_of Hash, result
      assert result.key?(:columns)
      refute result.key?(:associations), "columns detail should not include associations"
    end
  end

  def test_read_model_detail_validations
    with_test_model do |model_name|
      result = @read_model.call(name: model_name, detail: "validations")
      assert_instance_of Hash, result
      assert result.key?(:validators)
    end
  end

  # --- ReadLog tests ---

  def test_read_log_defines_correct_params
    assert_equal "read_log", @read_log.name
    assert @read_log.parameters.key?(:lines)
    assert @read_log.parameters.key?(:level)
    assert @read_log.parameters.key?(:search)
    assert @read_log.parameters.key?(:file)
  end

  def test_read_log_file_not_found
    result = @read_log.call(file: "/nonexistent_dir_42/log.log")
    assert_instance_of Ask::Result, result
    assert result.error?
  end

  def test_read_log_returns_recent_lines
    with_temp_log("line 1\nline 2\nline 3\nERROR: something broke\nline 5\n") do |path|
      result = @read_log.call(file: path, lines: 3)
      assert_instance_of Hash, result
      assert_equal 3, result[:lines].size
      assert result[:lines].any? { |l| l.include?("ERROR") }
    end
  end

  def test_read_log_respects_max_lines
    with_temp_log((1..600).map { |i| "line #{i}" }.join("\n")) do |path|
      result = @read_log.call(file: path, lines: 600)
      assert result[:lines].size <= 500
    end
  end

  def test_read_log_filters_by_level
    with_temp_log("[INFO] Started\n[ERROR] Failed\n[WARN] Retrying\n[INFO] Done") do |path|
      result = @read_log.call(file: path, lines: 10, level: "ERROR")
      assert result[:lines].all? { |l| l.include?("[ERROR]") }
      assert_equal 1, result[:matched_lines]
    end
  end

  def test_read_log_filters_by_search
    with_temp_log("GET /users\nPOST /login\nGET /posts\nDELETE /users/1") do |path|
      result = @read_log.call(file: path, lines: 10, search: "GET")
      assert result[:lines].all? { |l| l.include?("GET") }
      assert_equal 2, result[:matched_lines]
    end
  end

  def test_read_log_executes_successfully
    with_app_root do |dir|
      log_dir = File.join(dir, "log")
      FileUtils.mkdir_p(log_dir)
      File.write(File.join(log_dir, "development.log"), "INFO line one\nERROR something broke\n")

      result = @read_log.call(lines: 10)
      assert_instance_of Hash, result
      assert_equal 2, result[:total_lines]
      assert_includes result[:lines].join, "something broke"
    end
  end

  # --- inheritance / audit ---

  def test_tool_inherits_from_ask_tool
    assert Ask::Ruby::Harness::Tools::RunCommand.ancestors.include?(Ask::Tool)
    assert Ask::Ruby::Harness::Tools::QueryDatabase.ancestors.include?(Ask::Tool)
    assert Ask::Ruby::Harness::Tools::ReadModel.ancestors.include?(Ask::Tool)
    assert Ask::Ruby::Harness::Tools::ReadLog.ancestors.include?(Ask::Tool)
  end

  def test_tool_inherits_audit_log_instrumentation
    assert_respond_to Ask::Ruby::Harness::Tools::RunCommand, :session_id
    assert_respond_to Ask::Ruby::Harness::Tools::RunCommand, :session_id=
    assert_respond_to Ask::Ruby::Harness::Tool, :session_id
  end

  def test_tool_call_invokes_audit_log
    Ask::Ruby::Harness::Tool.session_id = "test-session-123"

    log_entries = []
    subscriber = ActiveSupport::Notifications.subscribe("audit_log.ask_ruby_harness") do |_name, _start, _finish, _id, payload|
      log_entries << payload
    end

    result = @run_command.call(command: "echo ok")
    assert_instance_of Ask::Result, result

    assert_equal 1, log_entries.length
    assert_equal "run_command", log_entries.first[:tool_name]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    Ask::Ruby::Harness::Tool.session_id = nil
  end

  def test_tool_call_audit_log_includes_session_id
    Ask::Ruby::Harness::Tool.session_id = "session-456"

    entry = nil
    subscriber = ActiveSupport::Notifications.subscribe("audit_log.ask_ruby_harness") do |*args|
      entry = args.last
    end

    @run_command.call(command: "echo ok")

    assert_equal "session-456", entry[:session_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    Ask::Ruby::Harness::Tool.session_id = nil
  end

  def test_tool_call_audit_log_records_duration
    Ask::Ruby::Harness::Tool.session_id = "duration-test"

    entry = nil
    subscriber = ActiveSupport::Notifications.subscribe("audit_log.ask_ruby_harness") do |*args|
      entry = args.last
    end

    @run_command.call(command: "echo ok")

    assert entry[:duration_ms].is_a?(Integer), "duration should be an integer"
    assert_operator entry[:duration_ms], :>=, 0
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    Ask::Ruby::Harness::Tool.session_id = nil
  end

  private

  def with_app_root
    Dir.mktmpdir do |dir|
      orig_root = Ask::Ruby::Harness.app_root
      Ask::Ruby::Harness.app_root = dir
      yield dir
      Ask::Ruby::Harness.app_root = orig_root
    end
  end

  def with_env(overrides)
    original = overrides.to_h { |k, _| [k, ENV[k]] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def with_test_db
    require "active_record"
    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "test.db")
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db_path)
      ActiveRecord::Base.connection.create_table(:test_items, force: true) do |t|
        t.string :name
        t.integer :value
      end
      (0..4).each do |i|
        ActiveRecord::Base.connection.insert("INSERT INTO test_items (name, value) VALUES ('item_#{i}', #{i * 10})")
      end
      yield ActiveRecord::Base.connection
      ActiveRecord::Base.connection.disconnect!
    end
  end

  def with_temp_log(content)
    Dir.mktmpdir do |dir|
      log_path = Pathname.new(dir).join("test.log")
      log_path.write(content)
      yield log_path.to_s
    end
  end

  def with_test_model
    require "active_record" unless defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Base.connection.create_table(:test_profiles, force: true) do |t|
      t.string :name, null: false
      t.string :email
      t.integer :age
      t.timestamps
    end

    model = Class.new(ActiveRecord::Base) do
      self.table_name = "test_profiles"
      validates :name, presence: true
      has_many :nonexistent_dummy
    end
    self.class.const_set(:TestProfile, model)
    model.table_name # ensure it loads

    yield "ToolsTest::TestProfile"
  ensure
    self.class.send(:remove_const, :TestProfile) rescue nil
    ActiveRecord::Base.descendants.delete(model) if model && ActiveRecord::Base.descendants.include?(model)
    ActiveRecord::Base.connection.disconnect! if ActiveRecord::Base.connected?
  end
end
