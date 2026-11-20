# frozen_string_literal: true

require_relative '../lib/ruby-gem-release/version/references'
require_relative '../lib/ruby-gem-release/version/ruby_constant'

module ReleaseVersion
  def self.build(path:, constant:, readme_path:)
    patterns = [%r{dblock/ruby-gem-release(?:/\.github/workflows/release\.yml)?@v(?<version>\d+\.\d+\.\d+)(?![\w.+-])}]
    RubyGemRelease::Version::References.new(
      version: RubyGemRelease::Version::RubyConstant.new(path: path, constant: constant),
      references: { readme_path => patterns, 'docs/**/*.md' => patterns }
    )
  end
end
