# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/semantic_release'

RSpec.describe RubyGemRelease::SemanticRelease::VersionSelector do
  it 'increments from the released version and resets lower components' do
    { 'major' => '3.0.0', 'minor' => '2.5.0', 'patch' => '2.4.10', nil => nil }.each do |type, expected|
      expect(described_class.new.select(last_release: '2.4.9', release_type: type)).to eq(expected)
    end
  end

  it 'uses the configurable first version for any releasable type and skips otherwise' do
    %w[major minor patch].each do |type|
      expect(described_class.new.select(last_release: nil, release_type: type)).to eq('1.0.0')
      expect(described_class.new(first_version: '0.1.0').select(last_release: nil, release_type: type)).to eq('0.1.0')
    end
    expect(described_class.new.select(last_release: nil, release_type: nil)).to be_nil
  end

  it 'allows an explicit version to override analysis or force a release but never replace an existing release' do
    expect(described_class.new.select(last_release: '1.2.3', release_type: 'major', explicit_version: '1.2.4')).to eq('1.2.4')
    expect(described_class.new.select(last_release: nil, release_type: nil, explicit_version: '0.1.0')).to eq('0.1.0')
    expect(described_class.new.select(last_release: '1.2.3', release_type: nil, explicit_version: '')).to be_nil
    %w[1.2.3 1.0.0 01.2.4 1.2.4-beta.1].each do |version|
      expect { described_class.new.select(last_release: '1.2.3', release_type: nil, explicit_version: version) }.to raise_error(ArgumentError)
    end
    expect { described_class.new(first_version: 'invalid') }.to raise_error(ArgumentError)
    expect { described_class.new.select(last_release: nil, release_type: 'prerelease') }.to raise_error(ArgumentError)
  end
end
