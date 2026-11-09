# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../tasks/release_version'

RSpec.describe ReleaseVersion do
  let(:directory) { Dir.mktmpdir }
  let(:version_file) { File.join(directory, 'version.rb') }
  let(:readme_file) { File.join(directory, 'README.md') }
  let(:version) { described_class.new(path: version_file, constant: 'VERSION', readme_path: readme_file) }
  let(:readme) do
    <<~MARKDOWN
      workflow: dblock/ruby-gem-release/.github/workflows/release.yml@v0.2.0
      action: dblock/ruby-gem-release@v0.2.0
      other: another/action@v0.2.0
    MARKDOWN
  end

  before do
    File.write(version_file, "VERSION = '1.2.3'\n")
    File.write(readme_file, readme)
  end

  after { FileUtils.remove_entry(directory) }

  it 'increments the version while pinning only this action and workflow to the released version', :aggregate_failures do
    expected = readme.sub('release.yml@v0.2.0', 'release.yml@v1.2.3').sub('ruby-gem-release@v0.2.0', 'ruby-gem-release@v1.2.3')
    expect(version.increment!).to eq('1.2.4')
    expect(version.read).to eq('1.2.4')
    expect(File.read(readme_file)).to eq(expected)
  end

  it 'preserves non-default increments without advertising the unreleased version', :aggregate_failures do
    expect(version.increment!(part: :minor)).to eq('1.3.0')
    expect(File.read(readme_file)).to include('release.yml@v1.2.3')
  end

  it 'repeats a bump from the same release without changing the version or pins again' do
    2.times { expect(version.increment!(from: '1.2.3')).to eq('1.2.4') }
    expect(File.read(readme_file)).to include('release.yml@v1.2.3', 'ruby-gem-release@v1.2.3')
  end

  it 'fails before incrementing if README cannot be read', :aggregate_failures do
    File.delete(readme_file)
    expect { version.increment! }.to raise_error(Errno::ENOENT)
    expect(version.read).to eq('1.2.3')
  end
end
