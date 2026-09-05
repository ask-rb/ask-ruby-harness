# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

# Prefer the sibling checkout (matches test_helper's local-gem pattern).
sibling = File.expand_path("../../ask-local/lib", __dir__)
$LOAD_PATH.unshift(sibling) if File.directory?(sibling)
require "ask-local"

class DevUrlTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @orig_state = ENV["ASK_LOCAL_STATE_DIR"]
    ENV["ASK_LOCAL_STATE_DIR"] = @dir
    @orig_variant = ENV["ASK_LOCAL_VARIANT"]
    @tool = Ask::Ruby::Harness::Tools::DevUrl.new
  end

  def teardown
    ENV["ASK_LOCAL_STATE_DIR"] = @orig_state
    if @orig_variant
      ENV["ASK_LOCAL_VARIANT"] = @orig_variant
    else
      ENV.delete("ASK_LOCAL_VARIANT")
    end
    FileUtils.remove_entry(@dir)
  end

  def test_defines_correct_params
    assert_equal "dev_url", @tool.name
    assert @tool.parameters.key?(:action)
    assert @tool.parameters.key?(:name)
  end

  def test_list_empty
    result = @tool.call(action: "list")
    assert_instance_of Hash, result
    assert_equal 0, result[:count]
  end

  def test_list_with_alias_route
    store = Ask::Local::RouteStore.new(@dir)
    store.add_route("dockerapp.localhost", "127.0.0.1:8080", 0, kind: "tcp")
    result = @tool.call(action: "list")
    entry = result[:routes].first
    assert_equal "dockerapp.localhost", entry[:hostname]
    assert_includes entry[:url], "dockerapp.localhost"
    assert_equal false, entry[:supervised]
  end

  def test_get_resolves_variant_from_env
    ENV["ASK_LOCAL_VARIANT"] = "fix-ui"
    result = @tool.call(action: "get", name: "backend")
    assert_includes result[:url], "fix-ui.backend.localhost"
    assert_equal "fix-ui", result[:variant]
  ensure
    ENV.delete("ASK_LOCAL_VARIANT")
  end

  def test_get_without_name_fails
    result = @tool.call(action: "get")
    assert result.error?
    assert_match(/Name is required/, result.error_message)
  end

  def test_unknown_action_fails
    result = @tool.call(action: "bogus")
    assert result.error?
  end
end
