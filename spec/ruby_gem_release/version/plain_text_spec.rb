# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/version/plain_text'
require 'tmpdir'

RSpec.describe RubyGemRelease::Version::PlainText do
  around do |example|
    Dir.mktmpdir { |directory| Dir.chdir(directory) { example.run } }
  end

  it 'reads and updates plain text versions while preserving their line ending' do
    version = described_class.new
    ['', "\n", "\r\n"].each do |ending|
      File.write('VERSION', "1.2.3#{ending}")
      expect(version.read).to eq('1.2.3')
      expect(version.set!('2.3.4')).to eq('2.3.4')
      expect(File.read('VERSION')).to eq("2.3.4#{ending}")
      2.times { expect(version.increment!(from: '2.3.4')).to eq('2.3.5') }
      expect(File.read('VERSION')).to eq("2.3.5#{ending}")
    end
  end

  it 'increments major and minor versions from a supplied release' do
    File.write('VERSION', '1.2.3')
    version = described_class.new
    expect(version.next_version(part: :major)).to eq('2.0.0')
    expect(version.increment!(part: :minor, from: '3.4.5')).to eq('3.5.0')
    expect { version.increment!(part: :other) }.to raise_error(ArgumentError, /bump part/)
  end

  it 'rejects malformed or prerelease versions without modifying the file' do
    version = described_class.new(path: 'VERSION')
    ['01.2.3', '1.2.3.pre', "1.2.3\nextra", "1.2.3\r"].each do |content|
      File.write('VERSION', content)
      expect { version.read }.to raise_error(ArgumentError, /invalid version/)
      expect { version.set!('1.2.4') }.to raise_error(ArgumentError, /invalid version/)
      expect(File.read('VERSION')).to eq(content)
    end
    File.write('VERSION', '1.2.3')
    expect { version.set!('1.2.3.pre') }.to raise_error(ArgumentError, /invalid version/)
    expect(File.read('VERSION')).to eq('1.2.3')
  end
end
