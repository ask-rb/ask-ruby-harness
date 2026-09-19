# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      module Tools
        # Structured access to yamine's stable dev URLs: active routes,
        # plus name -> URL resolution that inherits the current directory's
        # variant context. Replaces scraping ports out of logs.
        #
        # yamine is an optional dependency: the tool degrades to a clear
        # failure result when the gem is absent so harness hosts without it
        # lose nothing.
        class DevUrl < Ask::Ruby::Harness::Tool
          description "List yamine dev-server routes and resolve stable " \
                       ".localhost URLs. Use instead of guessing ports: " \
                       "'list' shows every active route with its URL and " \
                       "backend; 'get' resolves a service name to its URL " \
                       "(inheriting the current worktree/variant context)."

          param :action, type: :string, desc: "list (default) or get", required: false
          param :name,   type: :string, desc: "Service name for get (e.g. backend)", required: false

          def execute(action: "list", name: nil)
            unless defined?(Yamine)
              begin
                require "yamine"
              rescue LoadError
                return Ask::Result.failure(
                  "yamine is not installed. Add `gem \"yamine\"` to the Gemfile " \
                  "for stable .localhost dev URLs."
                )
              end
            end

            case action
            when "get" then get(name)
            when "list" then list
            else Ask::Result.failure("Unknown action #{action.inspect}. Use 'list' or 'get'.")
            end
          end

          private

          def list
            store = Yamine::RouteStore.new(resolve_state_dir)
            routes = store.load_routes
            port = Yamine::ProxyControl.proxy_port(store)
            tls = Yamine::ProxyControl.proxy_tls(store)
            entries = routes.map do |route|
              {
                hostname: route["hostname"],
                url: Yamine::Hostname.url(route["hostname"], port: port, tls: tls),
                target: route["target"],
                kind: route["kind"],
                supervised: !route["spec"].nil?,
                pid: route["pid"]
              }
            end
            { routes: entries, proxy_port: port, count: entries.length }
          rescue Yamine::Error => e
            Ask::Result.failure(e.message)
          end

          def get(name)
            return Ask::Result.failure("Name is required for action 'get'.") if name.nil? || name.to_s.strip.empty?

            resolved = Yamine::Resolver.resolve(app_root.to_s, variant: ENV["ASK_LOCAL_VARIANT"])
            hostnames = Yamine::Hostname.build(
              app: Yamine::Sanitize.hostname_label(name),
              tlds: [resolved.tld || Yamine::Hostname::DEFAULT_TLD],
              variant: resolved.variant
            )
            store = Yamine::RouteStore.new(resolve_state_dir)
            port = Yamine::ProxyControl.proxy_port(store)
            tls = Yamine::ProxyControl.proxy_tls(store)
            url = Yamine::Hostname.url(hostnames.first, port: port, tls: tls)
            {
              name: name,
              url: url,
              variant: resolved.variant,
              tld: resolved.tld,
              registered: !store.find(hostnames.first).nil?
            }
          rescue Yamine::Error => e
            Ask::Result.failure(e.message)
          end

          # Bridge the ASK_LOCAL_STATE_DIR env var (used by the ask-local
          # harness) to yamine's YAMINE_STATE_DIR / default ~/.yamine path.
          def resolve_state_dir
            ENV["ASK_LOCAL_STATE_DIR"] || Yamine::Certs.state_dir
          end
        end
      end
    end
  end
end
