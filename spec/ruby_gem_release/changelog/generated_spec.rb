# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/changelog'
require 'tmpdir'

RSpec.describe RubyGemRelease::Changelog::Generated do
  let(:release) do
    RubyGemRelease::Release.new(version: '1.2.3', previous_version: '9.0.0', date: Date.new(2026, 11, 9),
                                notes: "### Features\n\n- Add an endpoint.")
  end

  around do |example|
    Dir.mktmpdir { |directory| Dir.chdir(directory) { example.run } }
  end

  it 'creates a changelog with generated notes and preserves them across release copies' do
    described_class.new.release!(release)
    expect(File.read('CHANGELOG.md')).to eq("# Changelog\n\n## 1.2.3 (2026/11/09)\n\n### Features\n\n- Add an endpoint.\n\n")
    described_class.new.prepare_next!(release.with_next_version('1.2.4'))
    expect(release.with_version('1.2.3').with_next_version('1.2.4').notes).to eq(release.notes)
    expect(release.notes).to be_frozen
  end

  it 'prepends a release without reformatting historical Markdown or mistaking fenced headings for releases' do
    history = "## 1.2.2 (2026/11/08)\r\n\r\n* Original   spacing.\r\n"
    prefix = "# Changelog\r\n\r\n```md\r\n## 1.2.3 (Example)\r\n```\r\n\r\n"
    File.write('CHANGELOG.md', prefix + history)
    described_class.new.release!(release)
    content = File.read('CHANGELOG.md')
    expect(content).to start_with("#{prefix}## 1.2.3 (2026/11/09)\r\n")
    expect(content).to end_with(history)
    expect(content).not_to match(/(?<!\r)\n/)
    expect { described_class.new.release!(release) }.to raise_error(ArgumentError, /already exists/)
  end

  it 'rejects missing or content-free notes before writing a file' do
    [nil, '', "### Features\n\n<!-- comment -->"].each do |notes|
      invalid = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: release.date, notes: notes)
      expect { described_class.new.release!(invalid) }.to raise_error(ArgumentError)
    end
    expect(File).not_to exist('CHANGELOG.md')
  end
end
