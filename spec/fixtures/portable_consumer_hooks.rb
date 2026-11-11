# frozen_string_literal: true

require_relative 'portable_consumer_support'
require_relative 'release_workflow'

PortableConsumer.configure_network
workflow = ProjectReleaseWorkflow.build(**PortableConsumer.workflow_options(nil).except(:version, :changelog))
RubyGemRelease::Workflow::Hooks::STAGES.each do |stage|
  %i[before after].each do |timing|
    workflow.public_send(timing, stage) do |ctx|
      PortableConsumer.record('hook', stage: ctx.stage, timing: ctx.hook, index: ctx.hook_index, **PortableConsumer.context(ctx))
    end
  end
end

desc 'Verify the prepared package'
task :test do
  raise 'Unexpected prepared version' unless RubyGemRelease::Package::RubyGem.new.version == ENV.fetch('RELEASE_VERSION')
end

PortableConsumer.record('invocation', task: ARGV.last)
workflow.install_tasks
