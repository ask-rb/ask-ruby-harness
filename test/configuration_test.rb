# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < Minitest::Test
  def test_default_values
    config = Ask::Ruby::Harness::Configuration.new
    assert_equal "gpt-4o", config.default_model
    assert_equal 25, config.max_turns
    assert_nil config.system_prompt
    assert_equal 5, config.tool_concurrency
    assert_equal [], config.tools
  end

  def test_defaults_are_mutable
    config = Ask::Ruby::Harness::Configuration.new
    config.default_model = "claude-sonnet-4"
    assert_equal "claude-sonnet-4", config.default_model
  end

  def test_tools_are_settable
    config = Ask::Ruby::Harness::Configuration.new
    config.tools = [:tool1, :tool2]
    assert_equal [:tool1, :tool2], config.tools
  end

  def test_system_prompt_settable
    config = Ask::Ruby::Harness::Configuration.new
    config.system_prompt = "You are a helpful assistant"
    assert_equal "You are a helpful assistant", config.system_prompt
  end

  def test_persistence_adapter_settable
    config = Ask::Ruby::Harness::Configuration.new
    config.persistence_adapter = :memory
    assert_equal :memory, config.persistence_adapter
  end

  def test_current_user_settable
    config = Ask::Ruby::Harness::Configuration.new
    config.current_user = -> { { id: 1 } }
    assert_equal 1, config.current_user.call[:id]
  end

  def test_max_session_age_and_max_sessions_settable
    config = Ask::Ruby::Harness::Configuration.new
    config.max_session_age = 86_400
    config.max_sessions = 100
    assert_equal 86_400, config.max_session_age
    assert_equal 100, config.max_sessions
  end

  def test_environment_builder
    config = Ask::Ruby::Harness::Configuration.new
    config.environment :production do |env|
      env.mode = :read_only
      env.allowed_commands = [/^rails /]
    end
    assert config.environments.key?(:production)
    assert_equal :read_only, config.environments[:production].mode
  end

  def test_effective_allowed_commands_uses_global_when_no_env_match
    config = Ask::Ruby::Harness::Configuration.new
    config.allowed_commands = [/^echo /]
    assert_equal config.allowed_commands, config.effective_allowed_commands
  end

  def test_effective_denied_commands_uses_global_when_no_env_match
    config = Ask::Ruby::Harness::Configuration.new
    config.denied_commands = [/rm/]
    assert_equal config.denied_commands, config.effective_denied_commands
  end

  def test_effective_mode_returns_nil_when_no_env_match
    config = Ask::Ruby::Harness::Configuration.new
    assert_nil config.effective_mode
  end

  def test_effective_rules_follow_the_current_environment
    with_env("APP_ENV" => "staging") do
      config = Ask::Ruby::Harness::Configuration.new
      config.environment :staging do |env|
        env.mode = :read_only
        env.allowed_commands = [/^bundle /]
        env.denied_commands = [/drop/]
      end

      assert_equal :read_only, config.effective_mode
      assert_equal [/^bundle /], config.effective_allowed_commands
      assert_equal [/drop/], config.effective_denied_commands
    end
  end

  def test_environment_defaults_remain_nil
    config = Ask::Ruby::Harness::Configuration.new
    config.environment(:production) { |_e| }
    assert_nil config.environments[:production].mode
    assert_nil config.environments[:production].allowed_commands
    assert_nil config.environments[:production].denied_commands
  end

  def test_database_config_keys_are_whitelisted
    assert_includes Ask::Ruby::Harness::Configuration::DATABASE_CONFIG_KEYS, "adapter"
    assert_includes Ask::Ruby::Harness::Configuration::DATABASE_CONFIG_KEYS, "url"
    refute_includes Ask::Ruby::Harness::Configuration::DATABASE_CONFIG_KEYS, "migrations_paths"
  end

  private

  def with_env(overrides)
    original = overrides.to_h { |k, _| [k, ENV[k]] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
