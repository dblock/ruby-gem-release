# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/changelog'
require 'ruby-gem-release/release'
require 'tmpdir'

RSpec.describe RubyGemRelease::Changelog::KeepAChangelog do
  let(:directory) { Dir.mktmpdir }
  let(:path) { File.join(directory, 'CHANGELOG.md') }
  let(:date) { Date.new(2026, 11, 7) }
  let(:release) { RubyGemRelease::Release.new(version: '1.0.0', previous_version: '1.0.0', date: date) }
  let(:next_release) { RubyGemRelease::Release.new(version: '1.0.0', previous_version: '1.0.0', next_version: '1.0.1', date: date) }

  after { FileUtils.remove_entry(directory) }

  [1, 3, 6].each do |level|
    it "preserves level #{level} headings across release and next-section preparation" do
      prefix = '#' * level
      history = "#{prefix} [0.9.0] - 2026-11-06\n\n- Older change.\n"
      File.write(path, "#{prefix} [Unreleased]\n\n- Change.\n\n#{history}")
      updater = described_class.new(path: path)
      updater.release!(release)
      updater.prepare_next!(next_release)
      expect(File.read(path)).to eq("#{prefix} [Unreleased]\n\n#{prefix} [1.0.0] - 2026-11-07\n\n- Change.\n\n#{history}")
    end
  end

  it 'rejects ambiguous release headings at different depths without writing', :aggregate_failures do
    content = "## [Unreleased]\n\n### [Unreleased]\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }.to raise_error(ArgumentError, /exactly one/)
    expect(File.read(path)).to eq(content)
  end

  it 'releases Keep a Changelog and opens the next section', :aggregate_failures do
    File.write(path, "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- Feature.\n")
    updater = described_class.new(path: path)
    updater.release!(release)
    expect(File.read(path)).to include("## [1.0.0] - 2026-11-07\n")
    updater.prepare_next!(next_release)
    expect(File.read(path)).to include("## [Unreleased]\n\n## [1.0.0] - 2026-11-07")
  end

  it 'rejects unsupported comparison links without changing the file', :aggregate_failures do
    content = "## [Unreleased]\n\n[Unreleased]: https://example.com/compare\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }
      .to raise_error(ArgumentError, /comparison URL/)
    expect(File.read(path)).to eq(content)
  end

  it 'updates comparison references across both phases while preserving history', :aggregate_failures do
    historical = "[0.9.0]: https://github.com/example/gem/compare/v0.8.0...v0.9.0\n[docs]: https://example.com\n"
    File.write(path, "## [Unreleased]\n\n- Change.\n\n[Unreleased]: https://github.com/example/gem/compare/v0.9.0...master\n#{historical}")
    updater = described_class.new(path: path)
    updater.release!(release)
    updater.prepare_next!(next_release)
    expect(File.read(path)).to include("[Unreleased]: https://github.com/example/gem/compare/v1.0.0...master\n[1.0.0]: https://github.com/example/gem/compare/v0.9.0...v1.0.0\n#{historical}")
    expect(File.read(path)).to include("## [Unreleased]\n\n## [1.0.0] - 2026-11-07")
  end

  it 'preserves unprefixed tags and CRLF comparison references' do
    File.write(path, "## [Unreleased]\r\n\r\n- Change.\r\n\r\n[Unreleased]: https://example.com/compare/0.9.0...HEAD\r\n")
    described_class.new(path: path).release!(release)
    expect(File.binread(path)).to include("[Unreleased]: https://example.com/compare/1.0.0...HEAD\r\n[1.0.0]: https://example.com/compare/0.9.0...1.0.0\r\n")
  end

  it 'rejects duplicate reference definitions without writing', :aggregate_failures do
    content = "## [Unreleased]\n\n[Unreleased]: https://example.com/compare/0.9.0...HEAD\n[unreleased]: https://example.com/compare/0.8.0...HEAD\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }.to raise_error(ArgumentError, /duplicate/)
    expect(File.read(path)).to eq(content)
  end

  it 'rejects an existing released-version reference without writing', :aggregate_failures do
    content = "## [Unreleased]\n\n[Unreleased]: https://example.com/compare/0.9.0...HEAD\n[1.0.0]: https://example.com/release\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }.to raise_error(ArgumentError, /already exists/)
    expect(File.read(path)).to eq(content)
  end

  it 'ignores reference definitions inside code and HTML blocks' do
    content = "## [Unreleased]\n\n```\n[Unreleased]: not-a-comparison\n```\n\n<div>\n[Unreleased]: also-not-a-comparison\n</div>\n"
    File.write(path, content)
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to eq(content.sub('## [Unreleased]', '## [1.0.0] - 2026-11-07'))
  end

  it 'does not rewrite reference-like text inside a paragraph' do
    content = "## [Unreleased]\n\nExample text\n[Unreleased]: https://example.com/compare/0.9.0...HEAD\n"
    File.write(path, content)
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to eq(content.sub('## [Unreleased]', '## [1.0.0] - 2026-11-07'))
  end

  it 'rejects a stale Unreleased link when preparing the next section', :aggregate_failures do
    content = "## [1.0.0] - 2026-11-07\n\n[Unreleased]: https://example.com/compare/0.9.0...HEAD\n"
    File.write(path, content)
    expect { described_class.new(path: path).prepare_next!(next_release) }
      .to raise_error(ArgumentError, /released version/)
    expect(File.read(path)).to eq(content)
  end

  it 'ignores headings inside HTML blocks and nested quoted fences' do
    content = "<div>\n## [Unreleased]\n</div>\n\n> ```\n> ## [Unreleased]\n> ```\n\n## [Unreleased]\n\n- Change.\n"
    File.write(path, content)
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to eq(content.sub("## [Unreleased]\n\n- Change", "## [1.0.0] - 2026-11-07\n\n- Change"))
  end

  ["\n", "\r\n"].each do |separator|
    ['', "### Added\n\n<!-- pending -->\n\n[Unreleased]: https://example.com/compare/0.9.0...HEAD\n"].each do |notes|
      it "rejects empty or structural-only notes #{notes.inspect} with #{separator.inspect} endings", :aggregate_failures do
        content = "### [Unreleased]\n\n#{notes}\n## [0.9.0] - 2026-11-06\n\n- Older notes.\n".gsub("\n", separator)
        File.write(path, content)
        expect { described_class.new(path: path).release!(release) }.to raise_error(ArgumentError, /1.0.0.*empty release notes.*CHANGELOG.md.*add release notes/)
        expect(File.binread(path)).to eq(content)
      end
    end
  end

  it 'accepts notes in deeper categories while preserving shallower history' do
    content = "### [Unreleased]\n\n#### Fixed\n\n- A fix with `code` and [documentation][docs].\n\n## History\n\n- Older notes.\n\n[docs]: https://example.com\n"
    File.write(path, content)
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to eq(content.sub('### [Unreleased]', '### [1.0.0] - 2026-11-07'))
  end

  it 'rejects ambiguous headings without changing the file', :aggregate_failures do
    content = "## [Unreleased]\n\n## [Unreleased]\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }
      .to raise_error(ArgumentError, /exactly one/)
    expect(File.read(path)).to eq(content)
  end

  it 'ignores headings inside fenced code' do
    File.write(path, "```markdown\n## [Unreleased]\n```\n\n## [Unreleased]\n\n- Change\n")
    described_class.new(path: path).release!(release)
    expect(File.read(path)).to include("```markdown\n## [Unreleased]\n```\n\n## [1.0.0] - 2026-11-07")
  end

  it 'rejects duplicate release headings without modifying the file', :aggregate_failures do
    content = "## [Unreleased]\n\n## [1.0.0] - 2026-01-01\n"
    File.write(path, content)
    expect { described_class.new(path: path).release!(release) }
      .to raise_error(ArgumentError, /already exists/)
    expect(File.read(path)).to eq(content)
  end
end
