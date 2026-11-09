# frozen_string_literal: true

require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'
require 'digest'

raise 'Unexpected Actions environment' if ENV.keys.any? { |name| name.start_with?('GITHUB_', 'RUNNER_', 'ACTIONS_', 'GH_') }

loaded = $LOADED_FEATURES.find { |path| path.end_with?('/ruby-gem-release/tasks.rb') }
expected = File.join(ENV.fetch('RELEASE_TEST_LIB'), 'ruby-gem-release/tasks.rb')
raise 'Consumer loaded the wrong release library' unless loaded && File.realpath(loaded) == File.realpath(expected)

module PortableConsumer
  def self.record(event, **attributes)
    File.open(File.join(ENV.fetch('RELEASE_DIRECTORY'), 'events.jsonl'), 'a') do |file|
      file.puts JSON.generate({ event: event, pid: Process.pid }.merge(attributes))
    end
  end

  def self.context(ctx)
    { step: ctx.step.id, context_class: ctx.class.name, steps: ctx.steps, run: ctx.run,
      version: ctx.release&.version, previous_version: ctx.release&.previous_version, next_version: ctx.release&.next_version,
      provider: ctx.workflow.provider.class.name }
  end

  def self.remote_tags
    output, error, status = Open3.capture3('git', '--git-dir', ENV.fetch('RELEASE_TEST_REMOTE'), 'tag')
    raise error unless status.success?

    output.lines.map(&:strip)
  end

  class Provider < RubyGemRelease::ExecutionProvider
    def export(values)
      super
      File.write(fetch('CONSUMER_ENVIRONMENT'), JSON.generate(values))
    end

    def output(values)
      super
      File.write(fetch('CONSUMER_OUTPUT'), JSON.generate(outputs))
    end

    def failed_steps
      JSON.parse(fetch('CONSUMER_FAILURES', '[]'))
    end
  end

  class Destination < RubyGemRelease::Destination
    def check_version!(name:, version:)
      PortableConsumer.record('check', name: name, version: version)
    end

    def publish!(release, package:)
      path = package.artifact(release)
      PortableConsumer.record('publish', path: path, sha256: Digest::SHA256.file(path).hexdigest, tags: PortableConsumer.remote_tags)
      raise 'Registry rejected release' if ENV['CONSUMER_FAIL_PUBLICATION'] == 'true'
    end
  end

  class Hosting
    def publish!(release, package:)
      path = package.artifact(release)
      PortableConsumer.record('hosting', path: path, sha256: Digest::SHA256.file(path).hexdigest, tags: PortableConsumer.remote_tags)
    end
  end

  module LocalCommands
    def capture3(*command)
      ruby = command.first == Gem.ruby && (command[1] == '-rrubygems' || command[1, 3] == %w[-S gem build])
      raise 'Unexpected external command' unless command.first == 'git' || ruby

      super
    end
  end

  module NoNetwork
    def start(*)
      raise 'Unexpected network request'
    end
  end
end

Open3.singleton_class.prepend(PortableConsumer::LocalCommands)
Net::HTTP.singleton_class.prepend(PortableConsumer::NoNetwork)

RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new,
  provider: PortableConsumer::Provider.new,
  destination: PortableConsumer::Destination.new,
  hosting: PortableConsumer::Hosting.new,
  validate: lambda { |ctx|
    PortableConsumer.record('validate', **PortableConsumer.context(ctx))
    ctx.workflow.changelog.pending?
  },
  success: ->(ctx) { PortableConsumer.record('success', **PortableConsumer.context(ctx)) },
  failure: lambda { |failure|
    PortableConsumer.record('failure', phase: failure.phase, error: failure.error&.message, **PortableConsumer.context(failure.context))
  }
).install_tasks

desc 'Verify the prepared package'
task :test do
  raise 'Unexpected prepared version' unless RubyGemRelease::Package::RubyGem.new.version == ENV.fetch('RELEASE_VERSION')
end

PortableConsumer.record('invocation', task: ARGV.last)
