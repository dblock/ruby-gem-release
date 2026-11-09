# frozen_string_literal: true

require 'json'
require 'rubygems/package'
require 'ruby-gem-release/destination'

class FixtureRegistry < RubyGemRelease::Destination
  def authenticate!(provider:)
    provider.export('FIXTURE_REGISTRY_TOKEN' => 'fixture-registry-token')
  end

  def check_version!(name:, version:)
    File.open(File.join(ENV.fetch('RUNNER_TEMP'), 'registry-checks.jsonl'), 'a') do |file|
      file.puts JSON.generate([name, version])
    end
  end

  def publish!(release, package:)
    raise 'Registry authentication was not run before publication' unless ENV['FIXTURE_REGISTRY_TOKEN'] == 'fixture-registry-token'

    path = package.artifact(release)
    spec = Gem::Package.new(path).spec
    check_version!(name: spec.name, version: spec.version.to_s)
    File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'registry-publish.json'), JSON.generate(path))
  end
end
