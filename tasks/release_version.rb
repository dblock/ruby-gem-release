# frozen_string_literal: true

require_relative '../lib/ruby-gem-release/version/references'

class ReleaseVersion < RubyGemRelease::Version::References
  def initialize(readme_path:, **)
    patterns = [%r{dblock/ruby-gem-release(?:/\.github/workflows/release\.yml)?@v(?<version>\d+\.\d+\.\d+)(?![\w.+-])}]
    super(references: { readme_path => patterns, 'docs/**/*.md' => patterns }, **)
  end
end
