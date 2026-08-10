## [0.3.0] — 2026-08-10

### Added

- **Multi-database support in `QueryDatabase`** — new `database:` param to
  target any named database: a `config/database.yml` key (resolved first
  through the host app's own configurations registry, so Rails multi-DB
  apps work with credential-resolved configs) or a full connection URL.
  The result reports which database was queried. Write guards apply to all
  databases.

### Fixed

- **The gem now requires `active_record` itself** — previously the harness
  only loaded AR when the host did, so standalone processes (the MCP
  server) failed `ASK_DATABASE_URL` connections with "uninitialized
  constant ActiveRecord".

## [0.2.1] — 2026-08-10

### Fixed

- **Standalone DB connection guard** — `QueryDatabase` now checks whether a
  connection spec is *defined* (pool presence) instead of `connected?`
  (which stays false until the first checkout), so `establish_connection`
  from `ASK_DATABASE_URL`/`database.yml` is actually honored.
- **Relative sqlite paths in `database.yml`** — resolved against the app
  root (like Rails does) instead of the harness's cwd.

## [0.2.0] — 2026-08-10

### Added

- **Monorepo support in `run_tests`** — when the `file:` param points into a
  subproject (a directory with its own Gemfile/Rakefile), the suite runs
  there, so rake/rails resolve the subproject's tasks. Artifacts
  (`tmp/test/.ask/`) live in the subproject too. (The MCP server for this
  gem lives in the separate `ask-ruby-harness-mcp` gem.)

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
