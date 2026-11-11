# frozen_string_literal: true

require_relative 'portable_consumer_support'

PortableConsumer.install(validate: lambda { |ctx|
  PortableConsumer.record('validate', **PortableConsumer.context(ctx))
  ctx.workflow.changelog.pending?
})

desc 'Verify the prepared package'
task :test do
  raise 'Unexpected prepared version' unless RubyGemRelease::Package::RubyGem.new.version == ENV.fetch('RELEASE_VERSION')
end

PortableConsumer.record('invocation', task: ARGV.last)
