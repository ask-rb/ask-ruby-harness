source "https://rubygems.org"

gemspec

if File.directory?(File.expand_path("../ask-permissions", __dir__))
  gem "ask-permissions", path: "../ask-permissions"
end

group :test do
  gem "minitest", "~> 5.25"
  gem "mocha", "~> 3.1"
  gem "rake", "~> 13.0"
  gem "sqlite3", ">= 2.0"
end
