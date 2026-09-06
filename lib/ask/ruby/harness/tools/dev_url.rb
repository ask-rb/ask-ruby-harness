# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      module Tools
        # Structured access to ask-local's stable dev URLs: active routes,
        # plus name -> URL resolution that inherits the current directory's
        # variant context. Replaces scraping ports out of logs.
        #
        # ask-local is an optional dependency: the tool degrades to a clear
        # failure result when the gem is absent so harness hosts without it
        # lose nothing.
        class DevUrl < Ask::Ruby::Harness::Tool
          description "List ask-local dev-server routes and resolve stable " \
                       ".localhost URLs. Use instead of guessing ports: " \
                       "'list' shows every active route with its URL and " \
                       "backend; 'get' resolves a service name to its URL " \
                       "(inheriting the current worktree/variant context)."

          param :action, type: :string, desc: "list (default) or get", required: false
          param :name,   type: :string, desc: "Service name for get (e.g. backend)", required: false

          def execute(action: "list", name: nil)
            unless defined?(Ask::Local)
              begin
                require "ask-local"
              rescue LoadError
                return Ask::Result.failure(
                  "ask-local is not installed. Add `gem \"ask-local\"` to the Gemfile " \
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
            store = Ask::Local::RouteStore.new(Ask::Local::Certs.state_dir)
            routes = store.load_routes
            port = Ask::Local::ProxyControl.proxy_port(store)
            tls = Ask::Local::ProxyControl.proxy_tls(store)
            entries = routes.map do |route|
              {
                hostname: route["hostname"],
                url: Ask::Local::Hostname.url(route["hostname"], port: port, tls: tls),
                target: route["target"],
                kind: route["kind"],
                supervised: !route["spec"].nil?,
                pid: route["pid"]
              }
            end
            { routes: entries, proxy_port: port, count: entries.length }
          rescue Ask::Local::Error => e
            Ask::Result.failure(e.message)
          end

          def get(name)
            return Ask::Result.failure("Name is required for action 'get'.") if name.nil? || name.to_s.strip.empty?

            resolved = Ask::Local::Resolver.resolve(app_root.to_s)
            hostnames = Ask::Local::Hostname.build(
              app: Ask::Local::Sanitize.hostname_label(name),
              tlds: [resolved.tld || Ask::Local::Hostname::DEFAULT_TLD],
              variant: resolved.variant
            )
            store = Ask::Local::RouteStore.new(Ask::Local::Certs.state_dir)
            port = Ask::Local::ProxyControl.proxy_port(store)
            tls = Ask::Local::ProxyControl.proxy_tls(store)
            url = Ask::Local::Hostname.url(hostnames.first, port: port, tls: tls)
            {
              name: name,
              url: url,
              variant: resolved.variant,
              tld: resolved.tld,
              registered: !store.find(hostnames.first).nil?
            }
          rescue Ask::Local::Error => e
            Ask::Result.failure(e.message)
          end
        end
      end
    end
  end
end
