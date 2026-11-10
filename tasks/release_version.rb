# frozen_string_literal: true

require_relative '../lib/ruby-gem-release/version/ruby_constant'

class ReleaseVersion < RubyGemRelease::Version::RubyConstant
  def initialize(readme_path:, **)
    super(**)
    @readme_path = readme_path
  end

  def increment!(part: :patch, from: read)
    updates = [@readme_path, *Dir['docs/**/*.md']].filter_map do |path|
      original = File.read(path)
      updated = original.gsub(%r{(dblock/ruby-gem-release(?:/\.github/workflows/release\.yml)?@v)\d+\.\d+\.\d+}) do
        "#{Regexp.last_match(1)}#{from}"
      end
      [path, updated] unless original == updated
    end
    next_version = super
    updates.each { |path, content| File.write(path, content) }
    next_version
  end
end
