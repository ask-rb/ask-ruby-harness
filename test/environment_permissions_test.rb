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

  def test_agent_session_passes_env_mode_as_approval_mode
    with_configuration(Ask::Ruby::Harness.env.to_sym, :read_only) do
      captured = nil
      fake_session = Object.new
      Ask::Agent::Session.stub(:new, ->(**kwargs) { captured = kwargs; fake_session }) do
        assert_same fake_session, Ask::Ruby::Harness.agent_session
      end

      assert_equal({mode: :read_only}, captured[:approval])
      refute captured.key?(:hooks)
    end
  end

  def test_agent_session_preserves_caller_approval_options
    with_configuration(Ask::Ruby::Harness.env.to_sym, :read_only) do
      captured = nil
      Ask::Agent::Session.stub(:new, ->(**kwargs) { captured = kwargs; Object.new }) do
        Ask::Ruby::Harness.agent_session(approval: {queue: :custom, message: "Proceed?"})
      end

      assert_equal :read_only, captured[:approval][:mode]
      assert_equal :custom, captured[:approval][:queue]
      assert_equal "Proceed?", captured[:approval][:message]
    end
  end

  def test_agent_session_rejects_conflicting_caller_approval_mode
    with_configuration(Ask::Ruby::Harness.env.to_sym, :read_only) do
      error = assert_raises(ArgumentError) do
        Ask::Ruby::Harness.agent_session(approval: {mode: :full_access})
      end

      assert_match(/conflicting approval mode/, error.message)
      assert_match(/full_access/, error.message)
      assert_match(/read_only/, error.message)
    end
  end

  def test_agent_session_passes_no_forced_mode_without_env_config
    config = Ask::Ruby::Harness::Configuration.new
    config.environment(Ask::Ruby::Harness.env.to_sym) { |env| }
    with_configuration_object(config) do
      captured = nil
      Ask::Agent::Session.stub(:new, ->(**kwargs) { captured = kwargs; Object.new }) do
        Ask::Ruby::Harness.agent_session(approval: {mode: :ask_before_changes})
      end

      assert_nil Ask::Ruby::Harness.configuration.effective_mode
      assert_equal({mode: :ask_before_changes}, captured[:approval])
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
