# frozen_string_literal: true

require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/workflow/semantic_ruby_gem'
require 'ruby-gem-release/changelog'
require 'digest'

raise 'Unexpected Actions environment' if ENV.keys.any? { |name| name.start_with?('GITHUB_', 'RUNNER_', 'ACTIONS_', 'GH_') }

loaded = $LOADED_FEATURES.find { |path| path.end_with?('/ruby-gem-release/tasks.rb') }
expected = File.join(ENV.fetch('RELEASE_TEST_LIB'), 'ruby-gem-release/tasks.rb')
raise 'Consumer loaded the wrong release library' unless loaded && File.realpath(loaded) == File.realpath(expected)

module PortableConsumer
  def self.record(event, **attributes)
    File.open(File.join(ENV.fetch('RELEASE_DATA_DIR'), 'events.jsonl'), 'a') do |file|
      file.puts JSON.generate({ event: event, pid: Process.pid }.merge(attributes))
    end
  end

  def self.context(ctx)
    execution = { step: ctx.step.id, context_class: ctx.class.name, steps: ctx.steps, run: ctx.run, provider: ctx.workflow.provider.class.name }
    execution.merge(release_context(ctx))
  end

  def self.release_context(ctx)
    {
      version: ctx.release&.version, gemspec_version: ctx.release&.gemspec_version, next_version: ctx.release&.next_version,
      analysis: ctx.analysis&.to_h
    }
  end

  def self.remote_tags
    output, error, status = Open3.capture3('git', '--git-dir', ENV.fetch('RELEASE_TEST_REMOTE'), 'tag')
    raise error unless status.success?

    output.lines.map(&:strip)
  end

  class Provider < RubyGemRelease::ExecutionProvider
    def export(values)
      super
      path = fetch('CONSUMER_ENVIRONMENT')
      previous = File.file?(path) ? JSON.parse(File.read(path)) : {}
      File.write(path, JSON.generate(previous.merge(values)))
    end

    def failed_steps
      JSON.parse(fetch('CONSUMER_FAILURES', '[]'))
    end
  end

  class Destination < RubyGemRelease::Destination
    def authenticate!(**)
      PortableConsumer.record('authenticate')
    end

    def publish!(release, package:)
      return if published?(release, package: package)

      path = package.artifact(release)
      PortableConsumer.record('publish', path: path, sha256: Digest::SHA256.file(path).hexdigest, tags: PortableConsumer.remote_tags)
      raise 'Registry rejected release' if ENV['CONSUMER_FAIL_PUBLICATION'] == 'true'

      File.write(File.join(ENV.fetch('RELEASE_TEST_REMOTE'), 'registry.json'), JSON.generate(sha: Digest::SHA256.file(path).hexdigest))
    end

    def published?(release, package:)
      path = File.join(ENV.fetch('RELEASE_TEST_REMOTE'), 'registry.json')
      return false unless File.file?(path)
      raise 'Published checksum differs' unless JSON.parse(File.read(path)).fetch('sha') == Digest::SHA256.file(package.artifact(release)).hexdigest

      true
    end
  end

  class Hosting
    def publish!(release, package:)
      return if published?(release, package: package)

      path = package.artifact(release)
      PortableConsumer.record('hosting', path: path, sha256: Digest::SHA256.file(path).hexdigest, tags: PortableConsumer.remote_tags, notes: release.notes)
      File.write(File.join(ENV.fetch('RELEASE_TEST_REMOTE'), 'hosting.json'), JSON.generate(sha: Digest::SHA256.file(path).hexdigest))
    end

    def published?(release, package:)
      path = File.join(ENV.fetch('RELEASE_TEST_REMOTE'), 'hosting.json')
      return false unless File.file?(path)
      raise 'Hosted checksum differs' unless JSON.parse(File.read(path)).fetch('sha') == Digest::SHA256.file(package.artifact(release)).hexdigest

      true
    end
  end

  class SemanticDecision < RubyGemRelease::SemanticRelease
    def analyze(**arguments)
      raise 'Semantic analysis was repeated' if ENV['CONSUMER_FORBID_ANALYSIS'] == 'true'

      super.tap { |decision| PortableConsumer.record('analysis', decision: decision.to_h) }
    end
  end

  module LocalCommands
    def capture3(*command)
      arguments = command.first.is_a?(Hash) ? command.drop(1) : command
      ruby = arguments.first == Gem.ruby && (arguments[1] == '-rrubygems' || arguments[1, 3] == %w[-S gem build])
      raise 'Unexpected external command' unless arguments.first == 'git' || ruby

      super
    end
  end

  module NoNetwork
    def start(*)
      raise 'Unexpected network request'
    end
  end

  def self.install(validate: nil)
    configure_network
    workflow = build_workflow(validate)
    yield workflow if block_given?
    workflow.install_tasks
    workflow
  end

  def self.configure_network
    Open3.singleton_class.prepend(LocalCommands)
    Net::HTTP.singleton_class.prepend(NoNetwork)
  end

  def self.build_workflow(validate)
    return semantic_workflow if ENV['CONSUMER_SEMANTIC'] == 'true'

    standard_workflow(validate)
  end

  def self.semantic_workflow
    RubyGemRelease::Workflow::SemanticRubyGem.new(
      **workflow_options(RubyGemRelease::Changelog::Generated.new),
      semantic_release: SemanticDecision.new
    )
  end

  def self.standard_workflow(validate)
    RubyGemRelease::Workflow::RubyGem.new(
      **workflow_options(RubyGemRelease::Changelog::KeepAChangelog.new),
      validate: validate
    )
  end

  def self.workflow_options(changelog)
    {
      version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
      changelog: changelog,
      provider: Provider.new,
      destination: Destination.new,
      hosting: Hosting.new,
      **callback_options
    }
  end

  def self.callback_options
    {
      success: ->(ctx) { record('success', **context(ctx)) },
      failure: ->(failure) { record_failure(failure) }
    }
  end

  def self.record_failure(failure)
    record('failure', phase: failure.phase, error: failure.error&.message,
                      stage: failure.error&.stage, hook: failure.error&.hook, hook_index: failure.error&.hook_index,
                      **context(failure.context))
  end
end
