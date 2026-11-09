# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::State do
  it 'persists validated state across instances using private atomic files' do
    Dir.mktmpdir do |directory|
      path = described_class.create!(directory: directory)
      original = described_class.new(path: path)
      expect(original.next_version).to be_nil
      original.record_next_version!('1.2.4')
      expect(described_class.new(path: path).next_version).to eq('1.2.4')
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(Dir.children(directory)).to eq([File.basename(path)])
      expect { original.record_next_version!("1.2.4\nINJECTED=true") }.to raise_error(ArgumentError)
      expect(original.next_version).to eq('1.2.4')
    end
  end

  it 'creates isolated state for repeated invocations in the same runner directory' do
    Dir.mktmpdir do |directory|
      first = described_class.create!(directory: directory)
      second = described_class.create!(directory: directory)
      described_class.new(path: first).record_next_version!('1.2.4')
      expect(first).not_to eq(second)
      expect(described_class.new(path: second).next_version).to be_nil
    end
  end

  it 'fails closed for missing, corrupt, unsupported, or invalid persisted state' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'state.json')
      state = described_class.new(path: path)
      expect { state.next_version }.to raise_error(Errno::ENOENT)
      File.write(path, '{')
      expect { state.next_version }.to raise_error(JSON::ParserError)
      [
        [],
        { 'schema_version' => 2, 'next_version' => nil },
        { 'schema_version' => 1 },
        { 'schema_version' => 1, 'next_version' => '01.2.3' },
        { 'schema_version' => 1, 'next_version' => nil, 'extra' => 'unsupported' }
      ].each do |attributes|
        File.write(path, JSON.generate(attributes))
        expect { state.next_version }.to raise_error(ArgumentError)
        expect { state.record_next_version!('1.2.4') }.to raise_error(ArgumentError)
      end
    end
  end
end
