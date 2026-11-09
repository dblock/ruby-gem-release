# frozen_string_literal: true

require 'json'
require 'rubygems/package'
require 'ruby-gem-release/destination'

class FixtureRegistry < RubyGemRelease::Destination
  def check_version!(name:, version:)
    File.open(File.join(ENV.fetch('RUNNER_TEMP'), 'registry-checks.jsonl'), 'a') do |file|
      file.puts JSON.generate([name, version])
    end
  end

  def publish!(release, package:)
    path = package.artifact(release)
    spec = Gem::Package.new(path).spec
    check_version!(name: spec.name, version: spec.version.to_s)
    File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'registry-publish.json'), JSON.generate(path))
  end
end
