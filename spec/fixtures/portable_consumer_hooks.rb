# frozen_string_literal: true

require_relative 'portable_consumer_support'
require_relative 'release_notes'

PortableConsumer.install do |workflow|
  RubyGemRelease::Workflow::Hooks::STAGES.each do |stage|
    %i[before after].each do |timing|
      workflow.public_send(timing, stage) do |ctx|
        PortableConsumer.record('hook', stage: ctx.stage, timing: ctx.hook, index: ctx.hook_index, **PortableConsumer.context(ctx))
      end
    end

    desc 'Verify the prepared package'
    task :test do
      raise 'Unexpected prepared version' unless RubyGemRelease::Package::RubyGem.new.version == ENV.fetch('RELEASE_VERSION')
    end

    PortableConsumer.record('invocation', task: ARGV.last)
  end
  notes = ProjectReleaseNotes.new
  workflow.before(:validate) { |ctx| notes.validate!(ctx) }
  workflow.before(:prepare_release) { |ctx| notes.clean_placeholders!(ctx) }
  workflow.after(:prepare_release) { |ctx| notes.update_stable_readme!(ctx) }
  workflow.after(:prepare_next) { |ctx| notes.restore_template!(ctx) }
  workflow.after(:prepare_next) { |ctx| notes.update_development_readme!(ctx) }
end
