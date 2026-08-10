## [0.1.0] — 2026-08-10

### Added

- **Generic harness for any Ruby project** — extracted from
  `ask-rails-harness`: `RunCommand`, `ReadLog`, `QueryDatabase`, `ReadModel`,
  `SchemaGraph`, and `RunTests` with a language-agnostic tool contract.
- **No Rails dependency** — the gem loads in plain Ruby projects; database
  access connects standalone via `ASK_DATABASE_URL` or `config/database.yml`.
- **Runner detection for `run_tests`** — `bin/rails test` (Rails apps),
  `bundle exec rspec` (rspec projects), or `bundle exec rake test` (plain
  Ruby projects), all with the same structured JSON results.
- **Minitest JSON reporter + plugin** — `minitest/ask_ruby_harness_plugin.rb`
  (minitest 5 auto-discovery, minitest 6 RUBYOPT injection), inert unless
  `ASK_TEST_JSON_PATH` is set.
- **Environment permissions** — per-environment modes and command
  allow/deny lists.
- **Audit logging** — `ask_audit_logs` table (when available) +
  `audit_log.ask_ruby_harness` notification, with sensitive-param redaction.
