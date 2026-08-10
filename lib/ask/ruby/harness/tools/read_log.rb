# frozen_string_literal: true

module Ask
  module Ruby
    module Harness
      module Tools
        class ReadLog < Ask::Ruby::Harness::Tool
          description "Read application log files with filtering. Supports standard " \
                       "log rotation. Reads from the end of the file (most recent first)."

          param :lines,  type: :integer, desc: "Number of recent lines (default 50, max 500)", required: false
          param :level,  type: :string, desc: "Filter by level: ERROR, WARN, INFO, DEBUG", required: false
          param :search, type: :string, desc: "Search term (plain text, case-insensitive)", required: false
          param :file,   type: :string, desc: "Log file name (default: log/<env>.log)", required: false

          MAX_LINES = 500
          LEVEL_PATTERNS = {
            "ERROR" => /\bERROR\b/i,
            "WARN"  => /\bWARN\b/i,
            "INFO"  => /\bINFO\b/i,
            "DEBUG" => /\bDEBUG\b/i
          }.freeze

          def execute(lines: 50, level: nil, search: nil, file: nil)
            max_lines = [lines.to_i, MAX_LINES].min
            log_path = resolve_log_path(file)

            unless log_path.exist?
              return Ask::Result.failure(
                "Log file not found: #{log_path}. The application may not have written any logs yet."
              )
            end

            raw_lines = read_all_log_files(log_path)
            return { lines: [], total_lines: 0, path: log_path.to_s } if raw_lines.empty?

            filtered = apply_filters(raw_lines, level: level, search: search)
            recent = filtered.last(max_lines).map(&:chomp)

            {
              lines: recent,
              total_lines: raw_lines.size,
              matched_lines: filtered.size,
              path: log_path.to_s,
              filters_applied: { level: level, search: search }.compact
            }
          end

          private

          def resolve_log_path(custom_path)
            return app_root.join(custom_path) if custom_path
            app_root.join("log", "#{Ask::Ruby::Harness.env}.log")
          end

          # Read from rotated archives too: log/production.log, .1, .2.gz, etc.
          def read_all_log_files(log_path)
            all_content = +""
            rotated_files(log_path).each do |path|
              content = read_file_content(path)
              all_content.prepend(content) if content
            end
            all_content.lines
          end

          def rotated_files(log_path)
            dir = log_path.dirname
            base = log_path.basename.to_s
            # Primary file, then rotated files in reverse order (oldest first, then primary last)
            pattern = File.join(dir, "#{base}.*")
            rotations = Dir[pattern].sort_by { |f| extract_rotation_number(f) }
            # Primary file is read last (most recent)
            rotations + [log_path.to_s]
          end

          def extract_rotation_number(path)
            File.basename(path).sub(/.*\.(\d+)(\.gz)?$/, '\1').to_i
          rescue
            0
          end

          def read_file_content(path)
            if path.to_s.end_with?(".gz")
              Zlib::GzipReader.open(path.to_s) { |gz| gz.read }
            else
              File.read(path.to_s)
            end
          rescue => e
            warn "[ReadLog] Could not read #{path}: #{e.message}"
            nil
          end

          def apply_filters(lines, level: nil, search: nil)
            filtered = lines
            filtered = filtered.select { |l| LEVEL_PATTERNS.fetch(level) { // }.match?(l) } if level
            filtered = filtered.select { |l| l.downcase.include?(search.downcase) } if search
            filtered
          end
        end
      end
    end
  end
end
