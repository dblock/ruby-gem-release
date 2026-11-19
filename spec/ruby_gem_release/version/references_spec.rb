# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/version/references'
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
      path: 'version.rb', constant: 'VERSION',
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
    expect { described_class.new(path: 'version.rb', constant: 'VERSION', references: { 'README.md' => [/no capture/] }) }.to raise_error(ArgumentError)
    expect { described_class.new(path: 'version.rb', constant: 'VERSION', references: { 'README.md' => /(?<version>\d+)/ }) }.to raise_error(ArgumentError)
    version = described_class.new(path: 'version.rb', constant: 'VERSION', references: { 'missing' => [/(?<version>\d+)/] })
    expect { version.increment! }.to raise_error(Errno::ENOENT)
    expect(version.read).to eq('1.2.3')
  end

  it 'expands globs at increment time and combines overlapping selectors before writing' do
    File.write('version.rb', "VERSION = '1.2.3'\n")
    FileUtils.mkdir_p('docs/nested')
    version = described_class.new(
      path: 'version.rb', constant: 'VERSION',
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
end
