# frozen_string_literal: true

require "json"
require "timeout"

module Ask
  module Ruby
    module Harness
      module Tools
        class RunTests < Ask::Ruby::Harness::Tool
          description "Run the project's test suite and return structured results — summary counts " \
                       "plus per-test file/line/message for failures, never raw terminal output. " \
                       "Detects the runner (bin/rails test, rspec, or rake test). Minitest gets a " \
                       "JSON reporter via the bundled minitest plugin; rspec uses its built-in JSON " \
                       "formatter. Rerun only the previous run's failures with failed_only."

          param :file, type: :string, desc: "Test file path(s) relative to the project root (comma-separated for multiple)", required: false
          param :name, type: :string, desc: "Test name pattern: minitest --name (string or /regex/), rspec -e", required: false
          param :failed_only, type: :boolean, desc: "Rerun only the tests that failed in the previous run", required: false
          param :timeout, type: :integer, desc: "Max seconds to wait before killing the run (default 300)", required: false

          DEFAULT_TIMEOUT = 300
          ARTIFACT_DIR = %w[tmp test .ask].freeze

          def execute(file: nil, name: nil, failed_only: false, timeout: DEFAULT_TIMEOUT)
            files = split_files(file)
            # Monorepo support: a file inside a subproject (a dir with its
            # own Gemfile/Rakefile) runs that project's suite.
            run_root = resolve_run_root(files)
            files = files.map { |f| rel_to_run_root(f, run_root) }
            runner = detect_runner(run_root)

            # rake test only takes files (TEST env); expand directory args to
            # their *_test.rb files. Rails and rspec expand dirs natively.
            if runner == :minitest
              expanded = expand_minitest_directories(files, run_root)
              return expanded unless expanded.is_a?(Array)
              files = expanded
            end

            failed_tests = failed_only ? load_failed_tests(run_root) : nil
            if failed_only && failed_tests.empty?
              return Ask::Result.failure("No failed tests from the previous run to rerun.")
            end

            artifact_dir = run_root.join(*ARTIFACT_DIR).tap(&:mkpath)
            log_path = artifact_dir.join("last-test.log")
            json_path = artifact_dir.join("last-test.json")
            status_path = artifact_dir.join("last-failures.json")

            # A child that produces no JSON must not be masked by a previous
            # run's stale file — parse_results only looks at this path.
            json_path.delete if json_path.exist?

            command, env = build_command(runner, files, name, failed_tests, json_path)
            outcome = run(command, env, log_path, timeout, run_root)

            results = parse_results(runner, json_path)
            unless results
              # A killed run can't produce results — report it structurally
              # instead of failing, so the agent still gets the artifact path.
              return Ask::Result.ok(data: timed_out_report(runner, command, env, outcome, status_path, log_path, run_root)) if outcome[:timed_out]

              return Ask::Result.failure(
                "Test run finished without machine-readable results (#{runner}); " \
                "full output at #{rel(log_path, run_root)}"
              )
            end

            report = build_report(runner, command, env, outcome, results, status_path, log_path, run_root)
            Ask::Result.ok(data: report)
          end

          private

          def split_files(file)
            return [] if file.nil? || file.to_s.strip.empty?
            file.split(",").map(&:strip).reject(&:empty?)
          end

          # Rails app → bin/rails test; rspec in the bundle with a spec/ dir →
          # rspec; anything else → minitest via rake test.
          def detect_runner(run_root)
            return :rails if run_root.join("bin", "rails").exist?
            lockfile = run_root.join("Gemfile.lock")
            rspec = lockfile.exist? && lockfile.read.include?("rspec")
            return :rspec if rspec && run_root.join("spec").directory?
            :minitest
          end

          # --- monorepo support -------------------------------------------

          # For a file inside a subproject of a monorepo (a dir with its own
          # Gemfile/Rakefile), run the suite there so rake/rails resolve the
          # subproject's tasks. Only when ALL files share the same subproject;
          # otherwise (or at the app root itself) fall back to app_root.
          def resolve_run_root(files)
            roots = files.map { |f| project_root_for(f) }.uniq
            roots.size == 1 && !roots.first.nil? ? roots.first : app_root
          end

          def project_root_for(file)
            dir = File.expand_path(File.dirname(file), app_root)
            root = app_root.to_s
            while dir != root && dir.start_with?(root + File::SEPARATOR)
              return Pathname.new(dir) if %w[Gemfile Rakefile].any? { |n| File.exist?(File.join(dir, n)) }
              dir = File.dirname(dir)
            end
            nil
          end

          def rel_to_run_root(file, run_root)
            Pathname.new(File.expand_path(file, app_root)).relative_path_from(run_root).to_s
          end

          # rake_test_loader requires each arg as a file — a directory arg
          # explodes ("cannot load such file -- .../test"). Replace directory
          # args with the *_test.rb files under them (relative to run_root),
          # mirroring the standard Rake::TestTask pattern.
          def expand_minitest_directories(files, run_root)
            files.flat_map do |f|
              dir = File.join(run_root.to_s, f)
              next f unless File.directory?(dir)

              matches = Dir.glob(File.join(dir, "**", "*_test.rb"))
                          .map { |m| Pathname.new(m).relative_path_from(run_root).to_s }
                          .uniq
              if matches.empty?
                return Ask::Result.failure("No *_test.rb files found under '#{f}'.")
              end
              matches
            end.uniq
          end

          def build_command(runner, files, name, failed_tests, json_path)
            case runner
            when :rspec
              args = ["bundle", "exec", "rspec"]
              args.concat(files)
              args.concat(failed_tests.map { |t| "#{t[:file]}:#{t[:line]}" }) if failed_tests
              args.concat(["-e", name]) if name
              args.concat(["--format", "json", "--out", json_path.to_s])
              [args, {}]
            when :rails
              # Rails' `rails test` passes CLI args straight to minitest.
              args = ["bin/rails", "test"]
              args.concat(files)
              args.concat(["-n", name]) if name
              args.concat(["-n", name_pattern(failed_tests)]) if failed_tests
              [args, injection_env(json_path)]
            else
              # Plain Ruby project: rake test. Rake::TestTask reads TESTOPTS
              # (passed to ruby's ARGV, where rake_test_loader keeps only
              # `-`-prefixed args — so options must use the attached
              # --name=... form) and TEST (single file); the JSON reporter
              # arrives via RUBYOPT like everywhere else.
              args = ["bundle", "exec", "rake", "test"]
              env = injection_env(json_path)
              # Rake::TestTask reads TEST/TESTOPTS from the environment, so
              # the child inherits whatever the parent run carried (nested
              # runs!) unless it's overwritten or cleared here — a stray TEST
              # pointing at the outer project's files would abort the inner
              # run before any test loads.
              env["TEST"] = files.any? ? files.join(",") : nil
              testopts = []
              testopts << "--name=#{name}" if name
              testopts << "--name=#{name_pattern(failed_tests)}" if failed_tests
              if testopts.empty?
                env["TESTOPTS"] = nil
              else
                # rake's test task runs ruby through the shell, so unquoted
                # TESTOPTS with `|` (failed_only alternations) or spaces gets
                # split into bogus commands. Quote each option so it survives
                # as one ARGV entry in rake_test_loader.
                env["TESTOPTS"] = testopts.map { |o| "\"#{o}\"" }.join(" ")
              end
              %w[TESTOPT TEST_OPTS TEST_OPT].each { |k| env[k] = nil }
              [args, env]
            end
          end

          # minitest 6 dropped both plugin auto-discovery and the -r option.
          # Activate the project's bundle first, then require the plugin by
          # absolute path — it pushes its extension, and init_plugins
          # registers the JSON reporter later.
          def injection_env(json_path)
            {
              "ASK_TEST_JSON_PATH" => json_path.to_s,
              "RUBYOPT" => "-rbundler/setup -r#{minitest_plugin_path}"
            }
          end

          def minitest_plugin_path
            spec = Gem.loaded_specs["ask-ruby-harness"]
            spec ||= Gem::Specification.find_by_name("ask-ruby-harness")
            File.join(spec.full_gem_path, "lib", "minitest", "ask_ruby_harness_plugin.rb")
          end

          # Minitest --name accepts a regexp; alternation runs exactly the
          # failed tests.
          def name_pattern(failed_tests)
            escaped = failed_tests.map { |t| Regexp.escape(t[:test_name]) }
            "/#{escaped.join('|')}/"
          end

          def run(command, env, log_path, timeout, run_root)
            # The harness server may run with a deliberately small pool
            # (e.g. RAILS_MAX_THREADS=1 in its MCP config). Test runs are a
            # separate concern — let them use the app's normal pool sizes and
            # their own bundle. All BUNDLE*/BUNDLER_* vars are stripped so
            # the child's `bundle exec` resolves the project's own Gemfile
            # from cwd (inherited BUNDLE_GEMFILE and BUNDLER_ORIG_* sentinels
            # would otherwise hijack it).
            child_env = env.merge("RAILS_MAX_THREADS" => nil)
            ENV.each_key { |k| child_env[k] = nil if k.start_with?("BUNDLE") }
            pid = Process.spawn(child_env, *command, chdir: run_root.to_s,
                                out: [log_path.to_s, "w"], err: [:child, :out])
            status = nil
            timed_out = false
            begin
              Timeout.timeout(timeout) { status = Process.wait2(pid).last }
            rescue Timeout::Error
              timed_out = true
              begin
                Process.kill("TERM", pid)
                sleep 0.2
                Process.kill("KILL", pid)
              rescue Errno::ESRCH, Errno::EPERM
                # Process already gone — nothing to kill.
              end
              status = Process.wait2(pid).last rescue nil
            end
            { exit_status: status&.exitstatus, timed_out: timed_out }
          end

          def build_report(runner, command, env, outcome, results, status_path, log_path, run_root)
            summary = results[:summary]
            failed_tests = results[:failed_tests]
            persist_failed_tests(runner, failed_tests, status_path)

            {
              framework: runner.to_s,
              command: command.join(" "),
              exit_status: outcome[:exit_status],
              timed_out: outcome[:timed_out],
              summary: summary,
              failed_tests: failed_tests,
              artifact: rel(log_path, run_root),
              next: summary[:failures] + summary[:errors] > 0 ? "run_tests(failed_only: true)" : nil
            }
          end

          def timed_out_report(runner, command, env, outcome, status_path, log_path, run_root)
            persist_failed_tests(runner, [], status_path)
            {
              framework: runner.to_s,
              command: command.join(" "),
              exit_status: outcome[:exit_status],
              timed_out: true,
              summary: nil,
              failed_tests: nil,
              artifact: rel(log_path, run_root),
              next: nil
            }
          end

          def parse_results(runner, json_path)
            return nil unless json_path.exist?
            payload = JSON.parse(json_path.read)
            runner == :rspec ? parse_rspec(payload) : parse_minitest(payload)
          rescue JSON::ParserError
            nil
          end

          def parse_minitest(payload)
            tests = payload["tests"] || []
            summary = {
              run: payload.fetch("run", tests.size),
              failures: payload.fetch("failures", 0),
              errors: payload.fetch("errors", 0),
              skips: payload.fetch("skips", 0)
            }
            failed_tests = tests.filter_map do |t|
              next unless %w[failed error].include?(t["status"])
              { file: t["file"], test_name: t["name"], line: t["line"], message: t["message"] }
            end
            { summary: summary, failed_tests: failed_tests }
          end

          def parse_rspec(payload)
            examples = payload["examples"] || []
            summary_payload = payload["summary"] || {}
            failed_examples = examples.select { |e| e["status"] == "failed" }
            pending = examples.count { |e| e["status"] == "pending" }
            summary = {
              run: summary_payload.fetch("example_count", examples.size),
              failures: summary_payload.fetch("failure_count", failed_examples.size),
              errors: 0,
              skips: summary_payload.fetch("pending_count", pending)
            }
            failed_tests = failed_examples.map do |e|
              exception = e["exception"] || {}
              {
                file: e["file_path"],
                test_name: e["full_description"],
                line: e["line_number"],
                message: exception["message"]
              }
            end
            { summary: summary, failed_tests: failed_tests }
          end

          def persist_failed_tests(runner, failed_tests, status_path)
            status_path.write(JSON.pretty_generate(framework: runner.to_s, failed_tests: failed_tests))
          end

          def load_failed_tests(run_root)
            path = run_root.join(*ARTIFACT_DIR, "last-failures.json")
            return [] unless path.exist?
            JSON.parse(path.read).fetch("failed_tests", []).map { |t| symbolize_keys(t) }
          rescue JSON::ParserError
            []
          end

          def symbolize_keys(hash)
            hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
          end

          def rel(path, base = app_root)
            path.relative_path_from(base).to_s
          end
        end
      end
    end
  end
end
