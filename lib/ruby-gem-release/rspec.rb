# frozen_string_literal: true

require 'tmpdir'
require_relative 'rspec/project'
require_relative 'rspec/provider'
require_relative 'rspec/publication'

module RubyGemRelease
  module RSpec
    def with_release_project
      Dir.mktmpdir('ruby-gem-release-') do |directory|
        yield Project.new(directory: directory)
      end
    end
  end
end
