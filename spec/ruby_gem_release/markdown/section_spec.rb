# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'ruby-gem-release/markdown/section'

RSpec.describe RubyGemRelease::Markdown::Section do
  subject(:section) { described_class.new(path: 'README.md', heading: '## Stable Release') }

  around do |example|
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) { example.run }
    end
  end

  ["\n", "\r\n"].each do |separator|
    it "substitutes all matching body text while preserving formatting and surrounding sections with #{separator.inspect} endings" do
      before = "# Project\n\nOld.*\n\n## Stable Release"
      body = "\n\n  Old.*\n\n### Details\n\n`Old.*`\n\n"
      after = "## Installation\n\nOld.*\n"
      File.binwrite('README.md', "#{before}#{body}#{after}".gsub("\n", separator))

      2.times { section.gsub!('Old.*', "New.\nMore.") }

      expected_body = "\n\n  New.\nMore.\n\n### Details\n\n`New.\nMore.`\n\n"
      expect(File.binread('README.md')).to eq("#{before}#{expected_body}#{after}".gsub("\n", separator))
    end
  end

  it 'supports regular expressions and replacement references without adding a final newline' do
    File.write('README.md', "## Stable Release\n\nVersion 1.2.0; version 2.3.0.")

    section.gsub!(/version (\d+)\.(\d+)\.\d+/i, 'Release \1.\2.9')

    expect(File.read('README.md')).to eq("## Stable Release\n\nRelease 1.2.9; Release 2.3.9.")
  end

  it 'preserves heading boundaries when matching boundary newlines or inserting into an empty body' do
    File.write('README.md', "## Stable Release\n\nOld.\n\n## Other\n\nKeep.\n")
    section.gsub!(/\A\s+|\s+\z/, '')
    expect(File.read('README.md')).to eq("## Stable Release\nOld.\n## Other\n\nKeep.\n")

    File.write('README.md', '## Stable Release')
    section.gsub!(/\A/, 'New.')
    expect(File.read('README.md')).to eq("## Stable Release\nNew.")

    File.write('README.md', "## Stable Release\n## Other\n")
    section.gsub!(/\A/, 'New.')
    expect(File.read('README.md')).to eq("## Stable Release\nNew.\n## Other\n")
  end

  it 'does not write when no body text matches, even if the heading or another section matches' do
    content = "## Stable Release\n\nKeep.\n\n## Other\n\nStable Release\n"
    File.write('README.md', content)
    allow(File).to receive(:write).and_call_original

    expect(section.gsub!('Stable Release', 'New.')).to be_nil

    expect(File).not_to have_received(:write)
    expect(File.read('README.md')).to eq(content)
  end

  it 'rejects substitutions that introduce unsupported line endings without writing' do
    content = "## Stable Release\n\nOld.\n"
    File.write('README.md', content)

    expect { section.gsub!('Old.', "New.\rBroken.") }.to raise_error(ArgumentError, /line endings/)

    expect(File.read('README.md')).to eq(content)
  end

  ["\n", "\r\n"].each do |separator|
    it "replaces the full body, preserves surrounding source, and accepts repetition with #{separator.inspect} endings" do
      before = "# Project\n\nAn introduction.\n\n## Stable Release"
      after = "## Installation\n\nKeep *this* formatting.\n"
      original = "#{before}\n\nOld paragraph.\n\n### Details\n\nOld details.\n\n#{after}"
      File.binwrite('README.md', original.gsub("\n", separator))
      section.validate!
      expect(File.binread('README.md')).to eq(original.gsub("\n", separator))

      2.times { section.replace!("New paragraph.\n\n    Indented code.\n") }

      expect(File.binread('README.md')).to eq("#{before}\n\nNew paragraph.\n\n    Indented code.\n\n#{after}".gsub("\n", separator))
    end
  end

  it 'ignores headings inside code blocks, quotes, and HTML examples' do
    examples = "```\n## Stable Release\n```\n\n> ## Stable Release\n\n<div>\n## Stable Release\n</div>\n\n"
    File.write('README.md', "#{examples}## Stable Release\n\nOld.\n")

    section.replace!('New.')

    expect(File.read('README.md')).to eq("#{examples}## Stable Release\n\nNew.\n")
  end

  it 'rejects missing and duplicate real headings without writing' do
    ["# Other\n\nOld.\n", "## Stable Release\n\nOld.\n\n## Stable Release\n\nOther.\n"].each do |content|
      File.write('README.md', content)
      expect { section.validate! }.to raise_error(ArgumentError, /exactly one matching heading/)
      expect { section.replace!('New.') }.to raise_error(ArgumentError, /exactly one matching heading/)
      expect { section.gsub!('Old.', 'New.') }.to raise_error(ArgumentError, /exactly one matching heading/)
      expect(File.read('README.md')).to eq(content)
    end
  end

  it 'matches the heading literally rather than as a regular expression' do
    literal = described_class.new(path: 'README.md', heading: '## Stable [Release]')
    File.write('README.md', "## Stable Release\n\nKeep.\n\n## Stable [Release]\n\nOld.\n")

    literal.replace!('New.')

    expect(File.read('README.md')).to eq("## Stable Release\n\nKeep.\n\n## Stable [Release]\n\nNew.\n")
  end

  it 'stops at a shallower heading and leaves it unchanged' do
    ['# History', "#\tHistory", "History\n======="].each do |following|
      File.write('README.md', "## Stable Release\n\nOld.\n\n#{following}\n\nKeep.\n")
      section.replace!('New.')
      expect(File.read('README.md')).to eq("## Stable Release\n\nNew.\n\n#{following}\n\nKeep.\n")
    end
  end

  it 'handles the last section with and without a final newline, including an empty body' do
    ['## Stable Release', "## Stable Release\n\nOld.", "## Stable Release\n\nOld.\n"].each do |content|
      File.write('README.md', content)
      section.replace!('New.')
      ending = content.end_with?("\n") ? "\n" : ''
      expect(File.read('README.md')).to eq("## Stable Release\n\nNew.#{ending}")
      section.replace!('')
      expect(File.read('README.md')).to eq("## Stable Release\n\n")
    end
  end

  it 'rejects mixed and unsupported line endings before editing' do
    ["## Stable Release\r\n\nOld.\n", "## Stable Release\rOld."].each do |content|
      File.binwrite('README.md', content)
      expect { section.replace!('New.') }.to raise_error(ArgumentError, /line endings/)
      expect { section.gsub!('Old.', 'New.') }.to raise_error(ArgumentError, /line endings/)
      expect(File.binread('README.md')).to eq(content)
    end
    File.write('README.md', "## Stable Release\n\nOld.\n")
    expect { section.replace!("New.\nMixed.\r\n") }.to raise_error(ArgumentError, /line endings/)
    expect(File.read('README.md')).to eq("## Stable Release\n\nOld.\n")
  end
end
