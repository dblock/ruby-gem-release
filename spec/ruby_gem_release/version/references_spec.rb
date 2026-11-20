# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/version/references'
require 'ruby-gem-release/version/ruby_constant'
require 'ruby-gem-release/version/plain_text'
require 'tmpdir'

RSpec.describe RubyGemRelease::Version::References do
  around do |example|
    Dir.mktmpdir { |directory| Dir.chdir(directory) { example.run } }
  end

  it 'updates configured captures to the released version across files, including repeated bumps', :aggregate_failures do
    File.write('version.rb', "VERSION = '1.2.3'\n")
    File.write('README.md', "owner/project@v0.1.0\ngem 'project', '0.1.0'\nother/project@v0.1.0\n")
    File.write('guide.md', "owner/project@v0.1.0\ngem 'project', '0.1.0'\nproject version: 0.1.0\n")
    version = described_class.new(
      version: RubyGemRelease::Version::RubyConstant.new(path: 'version.rb', constant: 'VERSION'),
      references: {
        'README.md' => [%r{owner/project@v(?<version>\d+\.\d+\.\d+)}],
        'guide.md' => [/gem 'project', '(?<version>\d+\.\d+\.\d+)'/, /project version: (?<version>\d+\.\d+\.\d+)/]
      }
    )
    2.times { expect(version.increment!(from: '1.2.3')).to eq('1.2.4') }
    expect(version.read).to eq('1.2.4')
    expect(File.read('README.md')).to eq("owner/project@v1.2.3\ngem 'project', '0.1.0'\nother/project@v0.1.0\n")
    expect(File.read('guide.md')).to eq("owner/project@v0.1.0\ngem 'project', '1.2.3'\nproject version: 1.2.3\n")
  end

  it 'rejects invalid patterns and fails before changing the version for unreadable files' do
    File.write('version.rb', "VERSION = '1.2.3'\n")
    underlying = RubyGemRelease::Version::RubyConstant.new(path: 'version.rb', constant: 'VERSION')
    expect { described_class.new(version: underlying, references: { 'README.md' => [/no capture/] }) }.to raise_error(ArgumentError)
    expect { described_class.new(version: underlying, references: { 'README.md' => /(?<version>\d+)/ }) }.to raise_error(ArgumentError)
    version = described_class.new(version: underlying, references: { 'missing' => [/(?<version>\d+)/] })
    expect { version.increment! }.to raise_error(Errno::ENOENT)
    expect(version.read).to eq('1.2.3')
  end

  it 'expands globs at increment time and combines overlapping selectors before writing' do
    File.write('version.rb', "VERSION = '1.2.3'\n")
    FileUtils.mkdir_p('docs/nested')
    version = described_class.new(
      version: RubyGemRelease::Version::RubyConstant.new(path: 'version.rb', constant: 'VERSION'),
      references: {
        'docs/**/*.md' => [/gem 'project', '(?<version>\d+\.\d+\.\d+)'/],
        'docs/./guide.md' => [%r{owner/project@v(?<version>\d+\.\d+\.\d+)}],
        'docs/empty/*.md' => [/(?<version>\d+)/],
        'docs/*' => [/extra: (?<version>\d+\.\d+\.\d+)/]
      }
    )
    File.write('docs/guide.md', "gem 'project', '0.1.0'\nowner/project@v0.1.0\nextra: 0.1.0\n")
    File.write('docs/nested/guide.md', "gem 'project', '0.1.0'\nowner/project@v0.1.0\n")
    File.write('docs/.hidden.md', "gem 'project', '0.1.0'\n")

    2.times { version.increment!(from: '1.2.3') }
    expect(File.read('docs/guide.md')).to eq("gem 'project', '1.2.3'\nowner/project@v1.2.3\nextra: 1.2.3\n")
    expect(File.read('docs/nested/guide.md')).to eq("gem 'project', '1.2.3'\nowner/project@v0.1.0\n")
    expect(File.read('docs/.hidden.md')).to eq("gem 'project', '0.1.0'\n")
  end

  it 'wraps a plain text version and forwards set and non-default increments' do
    File.write('VERSION', "1.2.3\n")
    File.write('README.md', "version: 0.1.0\n")
    version = described_class.new(
      version: RubyGemRelease::Version::PlainText.new,
      references: { 'README.md' => [/version: (?<version>\d+\.\d+\.\d+)/] }
    )

    expect(version.set!('2.0.0')).to eq('2.0.0')
    expect(File.read('README.md')).to eq("version: 0.1.0\n")
    2.times { expect(version.increment!(part: :minor, from: '2.0.0')).to eq('2.1.0') }
    expect(version.read).to eq('2.1.0')
    expect(File.read('README.md')).to eq("version: 2.0.0\n")
  end

  it 'supports a custom version without next_version or part keywords' do
    custom = Class.new do
      attr_reader :value

      def read
        @value || 'release-a'
      end

      def set!(value)
        @value = value
      end

      def increment!(from:)
        @value = "#{from}-next"
      end
    end.new
    File.write('README.md', "version: old\n")
    version = described_class.new(version: custom, references: { 'README.md' => [/version: (?<version>[\w-]+)/] })

    expect(version.increment!).to eq('release-a-next')
    expect(version.read).to eq('release-a-next')
    expect(File.read('README.md')).to eq("version: release-a\n")
    expect(version.set!('release-b')).to eq('release-b')
    expect(File.read('README.md')).to eq("version: release-a\n")
    expect(version).not_to respond_to(:next_version)
  end

  it 'rejects version objects missing read, set, or increment' do
    expect { described_class.new(version: Object.new, references: {}) }.to raise_error(ArgumentError, 'version object must implement read, set!, increment!')
    expect { described_class.new(version: Struct.new(:read, :increment!).new('1.2.3'), references: {}) }.to raise_error(ArgumentError, 'version object must implement set!')
  end

  it 'preserves the incremented version when a reference selector matches the version file', :aggregate_failures do
    File.write('version.rb', "VERSION = '1.2.3' # released 1.2.2\n")
    version = described_class.new(
      version: RubyGemRelease::Version::RubyConstant.new(path: 'version.rb', constant: 'VERSION'),
      references: { '*.rb' => [/released (?<version>\d+\.\d+\.\d+)/] }
    )

    2.times do
      expect(version.increment!(from: '1.2.3')).to eq('1.2.4')
      expect(File.read('version.rb')).to eq("VERSION = '1.2.4' # released 1.2.3\n")
    end
  end

  it 'does not write references when the wrapped increment rejects the release version' do
    File.write('VERSION', '1.2.3')
    File.write('README.md', "version: 0.1.0\n")
    version = described_class.new(
      version: RubyGemRelease::Version::PlainText.new,
      references: { 'README.md' => [/version: (?<version>\d+\.\d+\.\d+)/] }
    )

    expect { version.increment!(from: 'invalid') }.to raise_error(ArgumentError, /invalid version/)
    expect(File.read('VERSION')).to eq('1.2.3')
    expect(File.read('README.md')).to eq("version: 0.1.0\n")
  end
end
