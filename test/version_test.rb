# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class VersionTest < Minitest::Test
  def test_version_is_set
    assert_match(/\A\d+\.\d+\.\d+\z/, Ask::Ruby::Harness::VERSION)
  end

  def test_harness_tools_registry_is_defined
    assert Ask::Ruby::Harness::HARNESS_TOOLS.is_a?(Array)
    assert_includes Ask::Ruby::Harness::HARNESS_TOOLS, Ask::Ruby::Harness::Tools::RunCommand
    assert_includes Ask::Ruby::Harness::HARNESS_TOOLS, Ask::Ruby::Harness::Tools::QueryDatabase
    assert_includes Ask::Ruby::Harness::HARNESS_TOOLS, Ask::Ruby::Harness::Tools::ReadModel
    assert_includes Ask::Ruby::Harness::HARNESS_TOOLS, Ask::Ruby::Harness::Tools::ReadLog
    assert_includes Ask::Ruby::Harness::HARNESS_TOOLS, Ask::Ruby::Harness::Tools::SchemaGraph
    assert_includes Ask::Ruby::Harness::HARNESS_TOOLS, Ask::Ruby::Harness::Tools::RunTests
  end

  def test_app_root_defaults_to_working_directory
    Ask::Ruby::Harness.app_root = nil
    assert_equal Pathname.new(Dir.pwd), Ask::Ruby::Harness.app_root
  ensure
    Ask::Ruby::Harness.app_root = nil
  end

  def test_app_root_is_settable
    Ask::Ruby::Harness.app_root = "/tmp/project"
    assert_equal Pathname.new("/tmp/project"), Ask::Ruby::Harness.app_root
  ensure
    Ask::Ruby::Harness.app_root = nil
  end

  def test_env_detection
    original = { "RAILS_ENV" => ENV["RAILS_ENV"], "RACK_ENV" => ENV["RACK_ENV"], "APP_ENV" => ENV["APP_ENV"] }
    ENV["RAILS_ENV"] = nil
    ENV["RACK_ENV"] = nil
    ENV["APP_ENV"] = "staging"
    assert_equal "staging", Ask::Ruby::Harness.env

    ENV["APP_ENV"] = nil
    assert_equal "development", Ask::Ruby::Harness.env
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def test_harness_loads_active_record_when_required_standalone
    # Regression: the gem must require active_record itself — without it,
    # ASK_DATABASE_URL connections fail with "uninitialized constant
    # ActiveRecord" in the MCP server (the test helper masks this by
    # requiring active_record first).
    lib = File.expand_path("../lib", __dir__)
    _out, err, status = Open3.capture3(
      RbConfig.ruby, "-I", lib, "-e",
      'require "ask/ruby/harness"; exit(defined?(ActiveRecord::Base) ? 0 : 1)'
    )
    assert status.success?, "ask/ruby/harness must load ActiveRecord itself (stderr: #{err[0, 200]})"
  end
end
