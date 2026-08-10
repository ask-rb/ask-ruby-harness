require_relative "lib/ask/ruby/harness/version"

Gem::Specification.new do |spec|
  spec.name = "ask-ruby-harness"
  spec.version = Ask::Ruby::Harness::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Admin AI copilot for Ruby projects — structured DB access, logs, commands, and tests"
  spec.description = "Harness for AI coding agents working in any Ruby project. Ships a " \
                     "language-agnostic tool contract (RunCommand, ReadLog, QueryDatabase, " \
                     "ReadModel, SchemaGraph, RunTests) with structured returns, read-only DB " \
                     "enforcement, environment permissions, and audit logging. The Rails " \
                     "edition (ask-rails-harness) adds framework-native tools on top."
  spec.homepage = "https://github.com/ask-rb/ask-ruby-harness"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "ask-tools", ">= 0.1"
  spec.add_dependency "ask-tools-shell", ">= 0.1"
  spec.add_dependency "ask-agent", ">= 0.28.0"

  spec.add_development_dependency "sqlite3", ">= 2.0"
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 3.1"
  spec.add_development_dependency "rake", "~> 13.0"
end
