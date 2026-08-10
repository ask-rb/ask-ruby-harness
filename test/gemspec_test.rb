# frozen_string_literal: true

require_relative "test_helper"
require "rubygems/package"

class GemspecTest < Minitest::Test
  def setup
    @gemspec = Gem::Specification.load(File.expand_path("../ask-ruby-harness.gemspec", __dir__))
  end

  def test_gemspec_is_valid
    assert @gemspec, "gemspec should load"
  end

  def test_name_and_version
    assert_equal "ask-ruby-harness", @gemspec.name
    assert_equal Ask::Ruby::Harness::VERSION, @gemspec.version.to_s
  end

  def test_metadata_links
    assert_equal "https://github.com/ask-rb/ask-ruby-harness", @gemspec.homepage
    assert_equal @gemspec.homepage, @gemspec.metadata["source_code_uri"]
  end

  def test_required_ruby_version
    requirement = @gemspec.required_ruby_version
    assert requirement.satisfied_by?(Gem::Version.new("3.2.0"))
    refute requirement.satisfied_by?(Gem::Version.new("3.1.0"))
  end

  def test_all_lib_files_are_packaged
    lib_files = Dir["lib/**/*.rb"]
    lib_files.each do |f|
      assert_includes @gemspec.files, f, "#{f} should be in the packaged files"
    end
  end

  def test_no_rails_dependency
    deps = @gemspec.dependencies.map(&:name)
    refute_includes deps, "rails", "the generic gem must not depend on Rails"
    refute_includes deps, "railties"
  end

  def test_depends_on_the_ask_stack
    deps = @gemspec.dependencies.map(&:name)
    assert_includes deps, "ask-tools"
    assert_includes deps, "ask-tools-shell"
    assert_includes deps, "ask-agent"
    assert_includes deps, "activerecord"
  end
end
