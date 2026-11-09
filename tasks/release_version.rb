# frozen_string_literal: true

require_relative '../lib/ruby-gem-release/version/ruby_constant'

class ReleaseVersion < RubyGemRelease::Version::RubyConstant
  def initialize(readme_path:, **)
    super(**)
    @readme_path = readme_path
  end

  def increment!(part: :patch, from: read)
    released_version = from
    readme = File.read(@readme_path).gsub(%r{(dblock/ruby-gem-release(?:/\.github/workflows/release\.yml)?@v)\d+\.\d+\.\d+}) do
      "#{Regexp.last_match(1)}#{released_version}"
    end
    next_version = super
    File.write(@readme_path, readme)
    next_version
  end
end
