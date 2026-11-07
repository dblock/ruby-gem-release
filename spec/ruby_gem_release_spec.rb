# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyGemRelease do
  it 'loads through the public entry point' do
    expect(described_class).to be_a(Module)
  end
end
