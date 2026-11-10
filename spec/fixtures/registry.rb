# frozen_string_literal: true

require 'digest'
require 'json'
require 'rubygems/package'
require 'ruby-gem-release/destination'

class FixtureRegistry < RubyGemRelease::Destination
  def authenticate!(provider:)
    provider.export('FIXTURE_REGISTRY_TOKEN' => 'fixture-registry-token')
  end

  def publish!(release, package:)
    return if published?(release, package: package)

    raise 'Registry authentication was not run before publication' unless ENV['FIXTURE_REGISTRY_TOKEN'] == 'fixture-registry-token'

    record_publication(package.artifact(release))
  end

  def published?(release, package:)
    record_check(package.name, release.version)
    return false unless File.file?(publication_path)

    publication = JSON.parse(File.read(publication_path))
    return false unless publication.fetch('version') == release.version
    raise 'Registry checksum differs' unless publication.fetch('sha256') == Digest::SHA256.file(package.artifact(release)).hexdigest

    true
  end

  private

  def record_check(name, version)
    File.open(File.join(ENV.fetch('RUNNER_TEMP'), 'registry-checks.jsonl'), 'a') do |file|
      file.puts JSON.generate([name, version])
    end
  end

  def record_publication(path)
    spec = Gem::Package.new(path).spec
    File.write(publication_path, JSON.generate(name: spec.name, version: spec.version.to_s, sha256: Digest::SHA256.file(path).hexdigest))
    File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'registry-publish.json'), JSON.generate(path))
  end

  def publication_path
    File.join(ENV.fetch('RELEASE_TEST_SERVICE_DIRECTORY', ENV.fetch('RUNNER_TEMP')), 'registry-metadata.json')
  end
end
