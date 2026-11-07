# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/changelog'
require 'ruby-gem-release/release'
require 'tmpdir'

RSpec.describe RubyGemRelease::Changelog::Intridea do
  let(:directory) { Dir.mktmpdir }
  let(:path) { File.join(directory, 'CHANGELOG.md') }
  let(:date) { Date.new(2026, 11, 7) }
  let(:release) { RubyGemRelease::Release.new(version: '1.0.0', previous_version: '1.0.0', date: date) }
  let(:next_release) { RubyGemRelease::Release.new(version: '1.0.0', previous_version: '1.0.0', next_version: '1.0.1', date: date) }

  after { FileUtils.remove_entry(directory) }

  [1, 3, 4, 5, 6].each do |level|
    it "preserves level #{level} headings across release and next-section preparation" do # rubocop:disable RSpec/ExampleLength -- Exercise both phases and unchanged history.
      prefix = '#' * level
      history = "#{prefix} 0.9.0 (2026/11/06)\n\n* Older change.\n"
      File.write(path, "#{prefix} 1.0.0 (Next)\n\n* Change.\n* Your contribution here.\n\n#{history}")
      updater = described_class.new(path: path, placeholder: '* Your contribution here.')
      updater.release!(release)
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
    it "releases an empty section without extra blank lines using #{separator.inspect} endings" do
      history = ['## 0.9.0 (2026/11/06)', '', '- Older change.', ''].join(separator)
      File.write(path, ['## 1.0.0 (Next)', '', '- Your contribution here.', '', history].join(separator))
      described_class.new(path: path).release!(release)
      expect(File.binread(path)).to eq("## 1.0.0 (2026/11/07)#{separator}#{separator}#{history}")
    end
  end

  it 'releases an Intridea section and opens the next section', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Check both phases.
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
    File.write(path, "## 1.0.0 (Next)\r\n\r\n* Your contribution here.\r\n")
    updater = described_class.new(path: path, placeholder: '* Your contribution here.')
    updater.release!(release)
    updater.prepare_next!(next_release)
    expect(File.binread(path)).to eq("## 1.0.1 (Next)\r\n\r\n* Your contribution here.\r\n\r\n## 1.0.0 (2026/11/07)\r\n\r\n")
  end

  it 'rejects mixed line endings without modifying the file', :aggregate_failures do
    content = "## 1.0.0 (Next)\r\n\n- Your contribution here.\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }
      .to raise_error(ArgumentError, /line endings/)
    expect(File.binread(path)).to eq(content)
  end

  it 'rejects missing or duplicate placeholders without modifying the file', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Verify both invalid inputs leave the file unchanged.
    ['', "- Your contribution here.\n- Your contribution here.\n"].each do |section|
      content = "## 1.0.0 (Next)\n\n#{section}"
      File.write(path, content)
      expect { described_class.new(path: path).release!(release) }
        .to raise_error(ArgumentError, /placeholder/)
      expect(File.read(path)).to eq(content)
    end
  end
end
