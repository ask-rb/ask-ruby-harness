# frozen_string_literal: true

# Load paths for local ask-rb gems (prefer local over installed gems)
ask_rb_root = File.expand_path("../..", __dir__)
%w[ask-core ask-tools ask-tools-shell ask-schema ask-skills ask-auth ask-instrumentation ask-llm-providers ask-agent ask-ruby-harness ask-sandbox-providers ask-state-providers].each do |gem|
  lib = File.join(ask_rb_root, gem, "lib")
  $LOAD_PATH.unshift lib if File.directory?(lib)
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Deliberately NO Rails — this gem must load and test without it.
require "active_record"
require "ask"
require "ask-schema"
require "ask/tools/tool"
require "ask/tools/shell"
require "ask/result"

require "ask/ruby/harness"
require "ask/ruby/harness/audit_log"
require "ask/ruby/harness/environment_permissions"
require "ask/ruby/harness/tool"
require "ask/ruby/harness/tools/run_command"
require "ask/ruby/harness/tools/query_database"
require "ask/ruby/harness/tools/read_model"
require "ask/ruby/harness/tools/read_log"
require "ask/ruby/harness/tools/schema_graph"
require "ask/ruby/harness/tools/run_tests"
require "ask/ruby/harness/minitest_json_reporter"

require "minitest/autorun"
require "mocha/minitest"
