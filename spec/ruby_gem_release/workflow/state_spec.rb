# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::State do
  let(:decision) do
    RubyGemRelease::SemanticRelease::Decision.new(head: 'a' * 40, last_release: nil, commits: [],
                                                  release_type: 'minor', version: '1.0.0', notes: 'Generated notes.')
  end

  it 'roundtrips semantic decisions without losing them when recording the next version' do
    Dir.mktmpdir do |directory|
      path = described_class.create!(directory: directory)
      state = described_class.new(path: path)
      ctx = RubyGemRelease::ExecutionContext.new(release: nil, task: 'release:validate', state: state)
      ctx.record_analysis!(decision)
      expect(ctx.analysis).to be_nil
      later = described_class.new(path: path)
      expect(later.analysis.to_h).to eq(decision.to_h)
      later.record_next_version!('1.0.1')
      expect(described_class.new(path: path).analysis.to_h).to eq(decision.to_h)
      expect(described_class.new(path: path).next_version).to eq('1.0.1')
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect { state.record_analysis!(decision) }.to raise_error(ArgumentError, /already recorded/)
    end
  end

  it 'retains immutable process-local analysis and rejects unsupported payloads' do
    state = described_class.new
    expect { state.record_analysis!({}) }.to raise_error(ArgumentError, /semantic release decision/)
    state.record_analysis!(decision)
    state.record_next_version!('1.0.1')
    ctx = RubyGemRelease::ExecutionContext.new(release: nil, task: 'release:success', state: state)
    expect(ctx.analysis).to equal(decision)
    expect { state.record_analysis!(decision) }.to raise_error(ArgumentError, /already recorded/)
    Dir.mktmpdir do |directory|
      path = described_class.create!(directory: directory)
      File.write(path, JSON.generate('next_version' => nil, 'analysis' => {}))
      expect { described_class.new(path: path).next_version }.to raise_error(ArgumentError, /unsupported semantic decision/)
    end
  end

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
        {},
        { 'next_version' => nil },
        { 'analysis' => nil },
        { 'next_version' => '01.2.3', 'analysis' => nil },
        { 'next_version' => nil, 'analysis' => nil, 'extra' => 'unsupported' }
      ].each do |attributes|
        File.write(path, JSON.generate(attributes))
        expect { state.next_version }.to raise_error(ArgumentError)
        expect { state.record_next_version!('1.2.4') }.to raise_error(ArgumentError)
      end
    end
  end
end
