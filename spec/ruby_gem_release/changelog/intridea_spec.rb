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

  it 'ignores multiple placeholders during pending-note validation' do
    content = "### 1.0.0 (Next)\n\n#### Features\n\n* Your contribution here.\n\n#### Fixes\n\n* Your contribution here.\n"
    File.write(path, content)
    changelog = described_class.new(path: path, placeholder: '* Your contribution here.')
    expect(changelog.pending?).to be(false)
    expect(File.read(path)).to eq(content)
  end

  it 'accepts notes without a placeholder during pending-note validation' do
    File.write(path, "## 1.0.0 (Next)\n\n- Change.\n\n## 0.9.0 (2026/01/01)\n\n- Older.\n")
    expect(described_class.new(path: path).pending?).to be(true)
  end

  it 'rejects a placeholder marked differently from the configured one without writing', :aggregate_failures do
    content = "## 1.0.0 (Next)\n\n* Your contribution here.\n"
    File.write(path, content)
    expect { described_class.new(path: path).pending? }
      .to raise_error(ArgumentError, /placeholder "\* Your contribution here\." in .*CHANGELOG.md does not match the configured "- Your contribution here\."/)
    expect { described_class.new(path: path).release!(release) }.to raise_error(ArgumentError, /does not match the configured/)
    expect(File.read(path)).to eq(content)
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

  it 'removes multiple placeholders and carries subsections into the next section', :aggregate_failures do
    content = "### 1.0.0 (Next)\n\n#### Features\n\n* Feature.\n* Your contribution here.\n\n#### Fixes\n\n* Fix.\n* Your contribution here.\n\n### 0.9.0 (2026/11/06)\n\n* Older change.\n"
    File.write(path, content)
    updater = described_class.new(path: path, placeholder: '* Your contribution here.')

    updater.release!(release)
    updater.release!(release)
    expect(File.read(path)).to eq("### 1.0.0 (2026/11/07)\n\n#### Features\n\n* Feature.\n\n#### Fixes\n\n* Fix.\n\n### 0.9.0 (2026/11/06)\n\n* Older change.\n")

    updater.prepare_next!(next_release)
    updater.prepare_next!(next_release)
    expect(File.read(path)).to eq("### 1.0.1 (Next)\n\n#### Features\n\n* Your contribution here.\n\n#### Fixes\n\n* Your contribution here.\n\n### 1.0.0 (2026/11/07)\n\n#### Features\n\n* Feature.\n\n#### Fixes\n\n* Fix.\n\n### 0.9.0 (2026/11/06)\n\n* Older change.\n")
  end

  it 'drops configured sections without notes and restores them in the next section', :aggregate_failures do
    content = "### 1.0.0 (Next)\n\n#### Features\n\n* Your contribution here.\n\n#### Fixes\n\n* Fix.\n* Your contribution here.\n\n### 0.9.0 (2026/11/06)\n\n* Older change.\n"
    File.write(path, content)
    updater = described_class.new(path: path, placeholder: '* Your contribution here.', sections: %w[Features Fixes])

    2.times { updater.release!(release) }
    expect(File.read(path)).to eq("### 1.0.0 (2026/11/07)\n\n#### Fixes\n\n* Fix.\n\n### 0.9.0 (2026/11/06)\n\n* Older change.\n")

    2.times { updater.prepare_next!(next_release) }
    expect(File.read(path)).to eq("### 1.0.1 (Next)\n\n#### Features\n\n* Your contribution here.\n\n#### Fixes\n\n* Your contribution here.\n\n" \
                                  "### 1.0.0 (2026/11/07)\n\n#### Fixes\n\n* Fix.\n\n### 0.9.0 (2026/11/06)\n\n* Older change.\n")
  end

  it 'keeps empty subsections without configured sections' do
    File.write(path, "### 1.0.0 (Next)\n\n#### Features\n\n* Your contribution here.\n\n#### Fixes\n\n* Fix.\n* Your contribution here.\n")
    described_class.new(path: path, placeholder: '* Your contribution here.').release!(release)
    expect(File.read(path)).to eq("### 1.0.0 (2026/11/07)\n\n#### Features\n\n#### Fixes\n\n* Fix.\n")
  end

  it 'rejects invalid configured sections and level-seven section headings', :aggregate_failures do
    [%w[Fixes Fixes], [''], ["Two\nLines"], 'Fixes'].each do |sections|
      expect { described_class.new(path: path, sections: sections) }.to raise_error(ArgumentError, /sections must be an array of unique nonempty names/)
    end
    File.write(path, "###### 1.0.0 (2026/11/07)\n\n- Change.\n")
    expect { described_class.new(path: path, sections: %w[Fixes]).prepare_next!(next_release) }.to raise_error(ArgumentError, /deeper than level six/)
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

  it 'releases notes without a placeholder and restores it in the next section', :aggregate_failures do
    File.write(path, "# Changelog\n\n## 1.0.0 (Next)\n\n- Change.\n")
    changelog = described_class.new(path: path)
    changelog.release!(release)
    expect(File.read(path)).to include("## 1.0.0 (#{release.date.strftime('%Y/%m/%d')})\n\n- Change.\n")
    changelog.prepare_next!(release.with_next_version('1.0.1'))
    expect(File.read(path)).to start_with("# Changelog\n\n## 1.0.1 (Next)\n\n- Your contribution here.\n")
  end

  it 'writes release dates with a configured strftime format' do
    File.write(path, "### 1.0.0 (Next)\n\n- Change.\n- Your contribution here.\n")
    described_class.new(path: path, date_format: '%Y-%m-%d').release!(release)
    expect(File.read(path)).to start_with('### 1.0.0 (2026-11-07)')
  end

  it 'writes release dates with a configured callable' do
    File.write(path, "### 1.0.0 (Next)\n\n- Change.\n- Your contribution here.\n")
    described_class.new(path: path, date_format: ->(value) { "#{value.day} #{value.strftime('%b %Y')}" }).release!(release)
    expect(File.read(path)).to start_with('### 1.0.0 (7 Nov 2026)')
  end

  it 'treats a release heading in any date format as released' do
    File.write(path, "### 1.0.0 (2026-11-07)\n\n- Change.\n\n### 0.9.0 (2026/11/06)\n\n- Older.\n")
    changelog = described_class.new(path: path, date_format: '%Y-%m-%d')
    expect(changelog.released?('1.0.0')).to be(true)
    expect(changelog.released?('0.9.0')).to be(true)
    expect(changelog.released?('0.8.0')).to be(false)
  end

  it 'prepares the next section after a release written in a configured format' do
    File.write(path, "### 1.0.0 (Next)\n\n- Change.\n- Your contribution here.\n")
    changelog = described_class.new(path: path, date_format: '%Y-%m-%d')
    changelog.release!(release)
    changelog.prepare_next!(next_release)
    expect(File.read(path)).to eq("### 1.0.1 (Next)\n\n- Your contribution here.\n\n### 1.0.0 (2026-11-07)\n\n- Change.\n")
  end

  it 'rejects an empty, multiline, or non-String date_format' do
    expect { described_class.new(path: path, date_format: '') }.to raise_error(ArgumentError, /date_format/)
    expect { described_class.new(path: path, date_format: "%Y\n") }.to raise_error(ArgumentError, /date_format/)
    expect { described_class.new(path: path, date_format: 20_261_107) }.to raise_error(ArgumentError, /date_format/)
  end

  [
    ['a format without date fields', 'Next'],
    ['a format that writes a newline', '%Y%n%m'],
    ['a callable returning an empty string', ->(_) { '' }],
    ['a callable returning nil', ->(_) {}],
    ['a callable returning a non-release word', ->(_) { 'Next' }],
    ['a callable returning a non-String', ->(_) { 20_261_107 }]
  ].each do |label, date_format|
    it "rejects #{label} without modifying the file" do
      content = "### 1.0.0 (Next)\n\n- Change.\n- Your contribution here.\n"
      File.write(path, content)
      expect { described_class.new(path: path, date_format: date_format).release!(release) }
        .to raise_error(ArgumentError, /date_format/)
      expect(File.read(path)).to eq(content)
    end
  end

  ['(next)', '(TBD)', '(Next)'].each do |text|
    it "does not treat the #{text} heading as released" do
      File.write(path, "### 1.0.0 #{text}\n\n- Change.\n")
      expect(described_class.new(path: path).released?('1.0.0')).to be(false)
    end
  end

  it 'rejects duplicate release headings written in different date formats' do
    File.write(path, "### 1.0.0 (2026/11/07)\n\n- Change.\n\n### 1.0.0 (2026-11-07)\n\n- Change.\n")
    expect { described_class.new(path: path).released?('1.0.0') }.to raise_error(ArgumentError, /duplicate release headings/)
  end

  describe '#notes' do
    it 'reads a released section with reference links expanded and rejects unreleased or invalid versions', :aggregate_failures do
      File.write(path, "# Changelog\n\n## 1.3.0 (Next)\n\n- Your contribution here.\n\n## 1.2.3 (2026/11/07)\n\n- [#1][pr]: Fix.\n\n## 1.2.2 (2026/11/06)\n\n- Older.\n\n[pr]: https://example.com/pull/1\n")
      changelog = described_class.new(path: path)
      expect(changelog.notes('1.2.3')).to eq('- [#1](<https://example.com/pull/1>): Fix.')
      expect { changelog.notes('1.3.0') }.to raise_error(ArgumentError)
      expect { changelog.notes('1.2') }.to raise_error(ArgumentError, /invalid version/)
    end
  end
end
