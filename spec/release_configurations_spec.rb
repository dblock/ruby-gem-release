# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'
require 'tmpdir'

RSpec.describe 'Documented release configurations' do
  let(:configuration) { File.read(File.expand_path('../examples/keep_a_changelog/Rakefile', __dir__)) }
  let(:changelog) { File.read(File.expand_path('../examples/keep_a_changelog/CHANGELOG.md', __dir__)) }
  let(:version) { RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION') }
  let(:objects) do
    {
      git: instance_double(RubyGemRelease::SourceControl::Git, commit!: nil, tag!: nil, push!: nil, commit_next!: nil),
      package: instance_double(RubyGemRelease::Package::RubyGem, name: 'example', build!: nil, built?: false),
      destination: instance_double(RubyGemRelease::Destination::RubyGems, authentication: nil, authenticate!: nil, publish!: nil),
      hosting: instance_double(RubyGemRelease::Hosting::GitHubRelease, publish!: nil)
    }
  end

  around do |example|
    application = Rake.application
    environment = ENV.to_h
    ENV.keys.grep(/\ARELEASE_/).each { |key| ENV.delete(key) }
    %w[GITHUB_ACTIONS GITHUB_OUTPUT].each { |key| ENV.delete(key) }
    ENV.update('INPUT_VERSION' => '', 'RELEASE_VERSION' => '0.1.0', 'GEMSPEC_VERSION' => '0.1.0', 'RELEASE_DATE' => '2026-11-09')
    Rake.application = Rake::Application.new
    Dir.mktmpdir { |directory| Dir.chdir(directory) { example.run } }
  ensure
    Rake.application = application
    ENV.replace(environment)
  end

  before do
    allow(RubyGemRelease::SourceControl::Git).to receive(:new).and_return(objects.fetch(:git))
    allow(objects.fetch(:git)).to receive(:stage_changes!) { |&block| block&.call }
    allow(RubyGemRelease::Package::RubyGem).to receive(:new).and_return(objects.fetch(:package))
    allow(objects.fetch(:package)).to receive(:version) { version.read }
    allow(RubyGemRelease::Destination::RubyGems).to receive(:new).and_return(objects.fetch(:destination))
    allow(RubyGemRelease::Hosting::GitHubRelease).to receive(:new).and_return(objects.fetch(:hosting))
    allow(Open3).to receive(:capture3).and_raise('Unexpected subprocess in release configuration spec')
    allow(Net::HTTP).to receive(:start).and_raise('Unexpected network request in release configuration spec')
    FileUtils.mkdir_p('lib/example')
    File.write('lib/example/version.rb', "module Example\n  VERSION = '0.1.0'\nend\n")
    File.write('CHANGELOG.md', changelog)
    File.write('Rakefile', configuration)
    load File.expand_path('Rakefile')
  end

  shared_examples 'a release configuration' do |format|
    ['', '2.0.0'].each do |selection|
      it "releases #{selection.empty? ? 'the checked-in version' : 'an explicit version'} and increments from it" do
        ENV['INPUT_VERSION'] = selection
        expected = selection.empty? ? '0.1.0' : selection
        next_version = selection.empty? ? '0.1.1' : '2.0.1'
        %w[validate prepare workflow:resolve publish bump].each { |task| Rake::Task["release:#{task}"].invoke }
        expect(objects.fetch(:package)).to have_received(:build!).with(have_attributes(version: expected, gemspec_version: '0.1.0', date: Date.new(2026, 11, 9)))
        expect(objects.fetch(:destination)).to have_received(:publish!).with(have_attributes(version: expected), package: objects.fetch(:package))
        expect(objects.fetch(:git)).to have_received(:commit_next!).with(have_attributes(version: expected, next_version: next_version))
        expect(version.read).to eq(next_version)
        heading = format == :intridea ? "### #{next_version} (Next)" : '## [Unreleased]'
        expect(File.read('CHANGELOG.md')).to include(heading)
      end
    end
  end

  it_behaves_like 'a release configuration', :keep_a_changelog

  context 'with third-level Intridea headings' do
    let(:configuration) { super().sub('Changelog::KeepAChangelog.new', "Changelog::Intridea.new(placeholder: '* Your contribution here.')") }
    let(:changelog) { "### 0.1.0 (Next)\n\n* Change.\n* Your contribution here.\n" }

    it_behaves_like 'a release configuration', :intridea
  end

  context 'with documented manual callbacks' do
    let(:configuration) { File.read(File.expand_path('../docs/usage.md', __dir__)).split('## Custom Callbacks').last[/```ruby\n(.*?)```/m, 1] }

    it_behaves_like 'a release configuration', :keep_a_changelog
  end
end
