# Ask Ruby Harness

Admin AI copilot for any Ruby project — structured, safe, permission-gated
access for coding agents. The language edition of the ask-rb harness family
(`ask-rails-harness` builds on this gem for Rails apps).

## What it gives agents

| Tool | What it does |
|---|---|
| `QueryDatabase` | Read-only SQL (non-SELECT rejected everywhere; SELECT-only in production) |
| `ReadModel` | Inspect an ActiveRecord model's columns, associations, validations |
| `ReadLog` | Read log files with level/search filtering and rotation support |
| `RunCommand` | Run shell commands in the project root, gated by permission rules |
| `SchemaGraph` | Full schema introspection: models, tables, columns, associations |
| `RunTests` | Structured test results with failure reruns (rails test / rspec / rake test) |

Generic file and search capabilities (read, grep, edit) are provided by the
agent's native tools; the harness focuses on what only an app-aware layer
can give an agent: database access, model introspection, logs, commands, and
tests — all structured, permission-gated, and audited.

## How it works

- **No Rails required.** The harness loads in any Ruby project. Database
  access connects standalone via `ASK_DATABASE_URL` or `config/database.yml`
  when the host hasn't already connected.
- **Structured returns, never terminal dumps.** Tools return data an agent
  can act on directly — `run_tests` reports counts plus per-test
  file/line/message.
- **Minitest JSON reporter.** `lib/minitest/ask_ruby_harness_plugin.rb` is
  auto-discovered by minitest 5 and injected via `RUBYOPT` on minitest 6
  (which dropped plugin auto-discovery). Only active when the harness starts
  the run (`ASK_TEST_JSON_PATH` set); ordinary test runs are untouched.
- **Audit logging.** Every tool call is recorded in `ask_audit_logs` (when
  the table exists) and broadcast as the `audit_log.ask_ruby_harness`
  ActiveSupport notification. Sensitive params are redacted.
- **Environment permissions.** Per-environment `mode` (full access, read
  only, ask before changes) and command allow/deny lists.

## Usage

```ruby
Ask::Ruby::Harness.configure do |config|
  config.environment :production do |env|
    env.mode = :read_only
    env.denied_commands = [/rm/, /dropdb/]
  end
end

Ask::Ruby::Harness.discover_tools!
session = Ask::Ruby::Harness.agent_session(model: "gpt-4o")
```

The Rails edition (`ask-rails-harness`) mounts an agent at `/ask` and adds
framework-native tools (routes, engine) on top of this gem.

## Development

```
bundle install
bundle exec rake test
```

## License

MIT — see LICENSE.
