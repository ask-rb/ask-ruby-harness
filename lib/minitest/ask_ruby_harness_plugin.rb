# frozen_string_literal: true

# Minitest plugin for ask-ruby-harness.
#
# Registers the JSON reporter when a run was started by the harness's
# run_tests tool (ASK_TEST_JSON_PATH set); ordinary test runs are untouched.
#
# Loading differs by minitest version:
#   - minitest 5 auto-discovers `minitest/*_plugin.rb` files and calls
#     init_plugins with `#{name}_plugin_init`.
#   - minitest 6 dropped auto-discovery; the run_tests tool injects this file
#     via RUBYOPT="-r <absolute path>" and init_plugins dispatches
#     `plugin_#{name}_init` instead.
# Either way, pushing the extension below (idempotent) makes init_plugins
# dispatch to the matching init method after the composite reporter exists —
# the only reliable point to append a reporter.
# __dir__-based requires keep the file loadable before Bundler.setup.
require File.expand_path("../ask/ruby/harness/minitest_json_reporter", __dir__)

module Minitest
  # Minitest 6 convention: init_plugins calls plugin_#{name}_init.
  def self.plugin_ask_ruby_harness_init(options)
    register_ask_ruby_harness_json_reporter(options)
  end

  # Minitest 5 convention: init_plugins calls #{name}_plugin_init.
  def self.ask_ruby_harness_plugin_init(options)
    register_ask_ruby_harness_json_reporter(options)
  end

  def self.register_ask_ruby_harness_json_reporter(_options)
    path = ENV["ASK_TEST_JSON_PATH"]
    return if path.nil? || path.to_s.empty?

    Minitest.reporter << Ask::Ruby::Harness::MinitestJsonReporter.new(path)
  end
end

Minitest.extensions << "ask_ruby_harness" unless Minitest.extensions.include?("ask_ruby_harness")
