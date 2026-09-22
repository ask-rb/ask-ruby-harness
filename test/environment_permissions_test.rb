# frozen_string_literal: true

require_relative "test_helper"

class EnvironmentPermissionsTest < Minitest::Test
  def test_defaults_are_nil
    env = Ask::Ruby::Harness::EnvironmentPermissions.new
    assert_nil env.mode
    assert_nil env.allowed_commands
    assert_nil env.denied_commands
  end

  def test_mode_is_settable
    env = Ask::Ruby::Harness::EnvironmentPermissions.new
    env.mode = :read_only
    assert_equal :read_only, env.mode
  end

  def test_allowed_commands_is_settable
    env = Ask::Ruby::Harness::EnvironmentPermissions.new
    env.allowed_commands = [/^rails /]
    assert_equal [/^rails /], env.allowed_commands
  end

  def test_denied_commands_is_settable
    env = Ask::Ruby::Harness::EnvironmentPermissions.new
    env.denied_commands = [/rm/]
    assert_equal [/rm/], env.denied_commands
  end

  def test_build_environment_hooks_wires_ask_permissions
    with_configuration(Ask::Ruby::Harness.env.to_sym, :read_only) do
      callback = Ask::Ruby::Harness.send(:build_environment_hooks).fetch(:before_tool).first
      assert_kind_of Ask::Permissions::Permissions, callback.receiver
      assert_equal :before_tool_call, callback.name
    end
  end

  def test_build_environment_hooks_is_empty_without_a_mode
    config = Ask::Ruby::Harness::Configuration.new
    config.environment(Ask::Ruby::Harness.env.to_sym) { |env| }
    with_configuration_object(config) do
      assert_empty Ask::Ruby::Harness.send(:build_environment_hooks)
    end
  end

  private

  def with_configuration(env_name, mode)
    config = Ask::Ruby::Harness::Configuration.new
    config.environment(env_name) { |env| env.mode = mode }
    with_configuration_object(config) { yield }
  end

  def with_configuration_object(config)
    original = Ask::Ruby::Harness.instance_variable_get(:@configuration)
    Ask::Ruby::Harness.instance_variable_set(:@configuration, config)
    yield
  ensure
    Ask::Ruby::Harness.instance_variable_set(:@configuration, original)
  end
end
