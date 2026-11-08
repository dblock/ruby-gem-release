# frozen_string_literal: true

require 'fileutils'

module RubyGemRelease
  module SourceControl
    class Git
      class Preparation
        def initialize(directory:, &command)
          @path = File.join(directory, 'prepared-tree')
          @command = command
        end

        def check_clean!
          entries = changes
          return if entries.empty?

          raise unexpected_changes('Release requires a clean checkout after dependency installation', entries)
        end

        def stage_changes!
          if block_given?
            check_clean!
            yield
          end
          paths = changed_paths
          run('--literal-pathspecs', 'add', '--', *paths) unless paths.empty?
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, run('write-tree').strip)
        end

        def verify!
          entries = changes
          return if entries.empty? && !File.file?(@path)

          prepared = File.file?(@path) && File.read(@path)
          staged_only = entries.all? { |entry| entry.first[1] == ' ' }
          return if staged_only && prepared == run('write-tree').strip

          raise unexpected_changes('Working tree or index changed outside release preparation; commit refused', entries)
        end

        def clear!
          FileUtils.rm_f(@path)
        end

        private

        def changed_paths
          changes.flat_map do |status, path, source|
            next [] if status[1] == ' '

            status[0].match?(/[RC]/) ? [path] : [path, source].compact
          end.uniq
        end

        def changes
          fields = run('status', '--porcelain=v1', '-z', '--untracked-files=all').split("\0")
          entries = []
          until fields.empty?
            field = fields.shift
            entry = [field[0, 2], field[3..]]
            entry << fields.shift if entry.first.match?(/[RC]/)
            entries << entry
          end
          entries
        end

        def unexpected_changes(message, entries)
          details = entries.first(20).map { |status, path, source| "  #{status} #{path.inspect}#{" (from #{source.inspect})" if source}" }
          details << "  ... #{entries.size - 20} more paths" if entries.size > 20
          "#{message} (#{entries.size} paths):\n#{details.join("\n")}\n" \
            'Remove generated files, restore unexpected tracked/index changes, or intentionally ignore dependency artifacts such as .bundle/config and vendor/bundle. ' \
            'Stage intended release edits with stage_changes! during preparation, not publication.'
        end

        def run(*)
          @command.call(*)
        end
      end
    end
  end
end
