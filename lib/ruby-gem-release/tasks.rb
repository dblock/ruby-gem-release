# frozen_string_literal: true

require 'rake'
require 'date'

module RubyGemRelease
  class Tasks
    include Rake::DSL

    VERSION_PATTERN = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/

    def self.install(version_file:, version_constant:)
      instance = new(version_file, version_constant)
      yield instance if block_given?
      instance.install
    end

    def initialize(version_file, version_constant)
      @version_file = version_file
      raise ArgumentError, 'version_constant must be a Ruby constant name' unless /\A[A-Z]\w*\z/.match?(version_constant)

      @assignment = /^([ \t]*#{Regexp.escape(version_constant)}[ \t]*=[ \t]*)(['"])([^'"\r\n]+)\2/
    end

    def install
      namespace :release do
        namespace :version do
          install_read_task
          install_set_task
          install_bump_task
        end
        install_callback_tasks
      end
    end

    def before_release(&block)
      raise ArgumentError, 'before_release requires a block' unless block
      raise ArgumentError, 'before_release already configured' if @before_release

      @before_release = block
    end

    def after_bump(&block)
      raise ArgumentError, 'after_bump requires a block' unless block
      raise ArgumentError, 'after_bump already configured' if @after_bump

      @after_bump = block
    end

    private

    def install_callback_tasks
      desc 'Run the before-release callback'
      task(:before_release, [:version]) do |_task, args|
        parse_version(args[:version])
        @before_release&.call(version: args[:version], date: Date.today)
      end
      desc 'Run the after-bump callback'
      task(:after_bump, [:released_version]) do |_task, args|
        parse_version(args[:released_version])
        @after_bump&.call(version: read, released_version: args[:released_version])
      end
    end

    def install_read_task
      desc 'Print the current version'
      task(:read) { puts read }
    end

    def install_set_task
      desc 'Set the version: rake release:version:set[1.2.3]'
      task(:set, [:version]) { |_task, args| write(args[:version]) }
    end

    def install_bump_task
      desc 'Bump the patch, minor, or major version (default: patch)'
      task(:bump, [:part]) { |_task, args| bump(args[:part] || 'patch') }
    end

    def bump(part)
      parts = parse_version(read)
      index = { 'major' => 0, 'minor' => 1, 'patch' => 2 }.fetch(part) do
        raise ArgumentError, 'bump part must be major, minor, or patch'
      end
      parts[index] += 1
      ((index + 1)...parts.size).each { |i| parts[i] = 0 }
      write(parts.join('.'))
    end

    def parse_version(version)
      match = VERSION_PATTERN.match(version.to_s)
      raise ArgumentError, "invalid version: #{version.inspect}; expected MAJOR.MINOR.PATCH" unless match

      match.captures.map(&:to_i)
    end

    def assignment(content)
      matches = content.to_enum(:scan, @assignment).map { Regexp.last_match }
      raise ArgumentError, "expected exactly one version assignment in #{@version_file}" unless matches.one?

      matches.first
    end

    def read
      version = assignment(File.read(@version_file))[3]
      parse_version(version)
      version
    end

    def write(version)
      parse_version(version)
      content = File.read(@version_file)
      match = assignment(content)
      content[match.begin(3)...match.end(3)] = version
      File.write(@version_file, content)
      puts version
    end
  end
end
