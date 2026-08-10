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
end
