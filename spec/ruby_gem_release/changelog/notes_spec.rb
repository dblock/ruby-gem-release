# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'ruby-gem-release/changelog/notes'

RSpec.describe RubyGemRelease::Changelog::Notes do
  let(:directory) { Dir.mktmpdir }
  let(:path) { File.join(directory, 'History.md') }

  after { FileUtils.remove_entry(directory) }

  it 'extracts a custom release section without changing the source or confusing fenced headings' do
    content = "# History\r\n\r\n## 8.0.0 / 2026-11-07\r\n\r\n### Changes\r\n\r\n- Fix.\r\n\r\n```\r\n## 8.0.0 / example\r\n```\r\n\r\n## 7.0.0 / 2025-01-01\r\n\r\nOld.\r\n"
    File.binwrite(path, content)
    reader = described_class.new(path: path, heading: ->(version) { %r{\A## #{Regexp.escape(version)} / \d{4}-\d{2}-\d{2}\z} })
    expect(reader.read('8.0.0')).to eq("### Changes\r\n\r\n- Fix.\r\n\r\n```\r\n## 8.0.0 / example\r\n```")
    expect(File.binread(path)).to eq(content)
  end

  it 'reads a release section with a date in any format by default' do
    File.write(path, "## 1.2.3 (2026-11-07)\n\n- Fix.\n\n## 1.2.2 (2026/11/06)\n\n- Older.\n")
    expect(described_class.new(path: path).read('1.2.3')).to eq('- Fix.')
  end

  it 'expands resolved reference links while leaving code and inline links unchanged' do
    content = "# History\n\n## 1.2.3 (2026/11/07)\n\n- Café [#42][pr], [inline](https://example.com), `[#42][pr]`, and [pr].\n\n```\n[#42][pr]\n```\n\n## Older\n\n[pr]: https://example.com/42 \"Title\"\n"
    File.write(path, content)
    notes = described_class.new(path: path, expand_references: true).read('1.2.3')
    expect(notes).to include('Café [#42](<https://example.com/42> "Title")', '[pr](<https://example.com/42> "Title")')
    expect(notes).to include('[inline](https://example.com)', '`[#42][pr]`', "```\n[#42][pr]\n```")
    expect(notes).not_to include('## Older', '[pr]:')
    expect(File.read(path)).to eq(content)
  end

  it 'rejects absent, duplicate, or empty release sections' do
    reader = described_class.new(path: path)
    File.write(path, "## Other\n\nNotes.\n")
    expect { reader.read('1.2.3') }.to raise_error(ArgumentError, /exactly one/)
    File.write(path, "## 1.2.3 (2026/11/07)\n\n## 1.2.3 (2026/11/07)\n")
    expect { reader.read('1.2.3') }.to raise_error(ArgumentError, /exactly one/)
    File.write(path, "## 1.2.3 (2026/11/07)\n\n### Changes\n\n<!-- comment -->\n")
    expect { reader.read('1.2.3') }.to raise_error(ArgumentError, /empty release notes/)
  end

  it 'drops link definitions trailing an expanded section but keeps them otherwise' do
    content = "## 1.0.0 (2026/11/07)\n\n- [Fix][1].\n\n[1]: https://example.com/1\n[Unreleased]: https://example.com/compare\n"
    File.write(path, content)
    expect(described_class.new(path: path, expand_references: true).read('1.0.0')).to eq('- [Fix](<https://example.com/1>).')
    expect(described_class.new(path: path).read('1.0.0')).to eq("- [Fix][1].\n\n[1]: https://example.com/1\n[Unreleased]: https://example.com/compare")
  end
end
