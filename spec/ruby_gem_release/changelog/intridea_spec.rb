# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/changelog'
require 'ruby-gem-release/release'
require 'tmpdir'

RSpec.describe RubyGemRelease::Changelog::Intridea do
  let(:directory) { Dir.mktmpdir }
  let(:path) { File.join(directory, 'CHANGELOG.md') }
  let(:date) { Date.new(2026, 11, 7) }
  let(:release) { RubyGemRelease::Release.new(version: '1.0.0', gemspec_version: '1.0.0', date: date) }
  let(:next_release) { RubyGemRelease::Release.new(version: '1.0.0', gemspec_version: '1.0.0', next_version: '1.0.1', date: date) }

  after { FileUtils.remove_entry(directory) }

  it 'ignores the custom placeholder and history when checking pending notes without writes' do
    content = "### 1.0.0 (Next)\r\n\r\n#### Fixed\r\n\r\n* Your contribution here.\r\n\r\n## 0.9.0 (2026/11/06)\r\n\r\n- Older notes.\r\n"
    File.write(path, content)
    changelog = described_class.new(path: path, placeholder: '* Your contribution here.')
    expect(changelog.pending?).to be(false)
    expect(File.binread(path)).to eq(content)
    File.write(path, content.sub('#### Fixed', "#### Fixed\r\n\r\n- A fix."))
    expect(changelog.pending?).to be(true)
  end

  it 'rejects missing and duplicate placeholders during validation rather than skipping' do
    ['', "- Your contribution here.\n- Your contribution here.\n"].each do |notes|
      content = "## 1.0.0 (Next)\n\n#{notes}"
      File.write(path, content)
      expect { described_class.new(path: path).pending? }.to raise_error(ArgumentError, /placeholder/)
      expect(File.read(path)).to eq(content)
    end
  end

  [1, 3, 4, 5, 6].each do |level|
    it "preserves level #{level} headings across release and next-section preparation" do
      prefix = '#' * level
      history = "#{prefix} 0.9.0 (2026/11/06)\n\n* Older change.\n"
      File.write(path, "#{prefix} 1.0.0 (Next)\n\n* Change.\n* Your contribution here.\n\n#{history}")
      updater = described_class.new(path: path, placeholder: '* Your contribution here.')
      updater.release!(release)
      updater.release!(release)
      updater.prepare_next!(next_release)
      updater.prepare_next!(next_release)
      expect(File.read(path)).to eq("#{prefix} 1.0.1 (Next)\n\n* Your contribution here.\n\n#{prefix} 1.0.0 (2026/11/07)\n\n* Change.\n\n#{history}")
    end
  end

  it 'keeps deeper subsections inside the release and stops at a shallower heading' do
    history = "## History\n\n### 0.9.0 (2026/11/06)\n\n- Your contribution here.\n"
    File.write(path, "### 1.0.0 (Next)\n\n#### Added\n\n- Change.\n- Your contribution here.\n\n#{history}")
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to eq("### 1.0.0 (2026/11/07)\n\n#### Added\n\n- Change.\n\n#{history}")
  end

  ["\n", "\r\n"].each do |separator|
    it "rejects placeholder-only notes using #{separator.inspect} endings without changing history", :aggregate_failures do
      history = ['## 0.9.0 (2026/11/06)', '', '- Older change.', ''].join(separator)
      content = ['## 1.0.0 (Next)', '', '- Your contribution here.', '', history].join(separator)
      File.write(path, content)
      expect { described_class.new(path: path).release!(release) }.to raise_error(ArgumentError, /empty release notes/)
      expect(File.binread(path)).to eq(content)
    end
  end

  it 'releases an Intridea section and opens the next section', :aggregate_failures do
    File.write(path, "# Changelog\n\n## 1.0.0 (Next)\n\n- Change.\n- Your contribution here.\n")
    updater = described_class.new(path: path)
    updater.release!(release)
    expect(File.read(path)).to eq("# Changelog\n\n## 1.0.0 (2026/11/07)\n\n- Change.\n")
    updater.prepare_next!(next_release)
    expect(File.read(path)).to include("## 1.0.1 (Next)\n\n- Your contribution here.\n\n## 1.0.0 (2026/11/07)")
  end

  it 'ignores fenced headings and placeholders while releasing an Intridea section' do
    content = "## 1.0.0 (Next)\n\n```\n## Example\n- Your contribution here.\n```\n\n- Your contribution here.\n"
    File.write(path, content)
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to eq("## 1.0.0 (2026/11/07)\n\n```\n## Example\n- Your contribution here.\n```\n\n")
  end

  it 'preserves CRLF and a configured star placeholder across phases' do
    File.write(path, "## 1.0.0 (Next)\r\n\r\n* Change.\r\n* Your contribution here.\r\n")
    updater = described_class.new(path: path, placeholder: '* Your contribution here.')
    updater.release!(release)
    updater.prepare_next!(next_release)
    expect(File.binread(path)).to eq("## 1.0.1 (Next)\r\n\r\n* Your contribution here.\r\n\r\n## 1.0.0 (2026/11/07)\r\n\r\n* Change.\r\n")
  end

  it 'rejects category headings, comments, and a custom placeholder without writing', :aggregate_failures do
    content = "### 1.0.0 (Next)\n\n#### Added\n\n<!-- pending -->\n\n* Your contribution here.\n\n## History\n\n- Older notes.\n"
    File.write(path, content)
    expect { described_class.new(path: path, placeholder: '* Your contribution here.').release!(release) }.to raise_error(ArgumentError, /1.0.0.*empty release notes.*CHANGELOG.md.*add release notes/)
    expect(File.read(path)).to eq(content)
  end

  it 'rejects mixed line endings without modifying the file', :aggregate_failures do
    content = "## 1.0.0 (Next)\r\n\n- Your contribution here.\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }
      .to raise_error(ArgumentError, /line endings/)
    expect(File.binread(path)).to eq(content)
  end

  it 'rejects missing or duplicate placeholders without modifying the file', :aggregate_failures do
    ['', "- Your contribution here.\n- Your contribution here.\n"].each do |section|
      content = "## 1.0.0 (Next)\n\n#{section}"
      File.write(path, content)
      expect { described_class.new(path: path).release!(release) }
        .to raise_error(ArgumentError, /placeholder/)
      expect(File.read(path)).to eq(content)
    end
  end
end
