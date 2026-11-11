# frozen_string_literal: true

require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'
require_relative 'release_notes'

module ProjectReleaseWorkflow
  def self.build(**)
    workflow = RubyGemRelease::Workflow::RubyGem.new(
      version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
      changelog: RubyGemRelease::Changelog::KeepAChangelog.new(
        placeholder: '* Your contribution here.',
        sections: %w[Added Changed Deprecated Removed Fixed Security]
      ),
      **
    )
    add_hooks(workflow)
    workflow
  end

  def self.add_hooks(workflow)
    notes = ProjectReleaseNotes.new
    workflow.before(:validate) { |ctx| notes.validate!(ctx) }
    workflow.after(:prepare_release) { |ctx| notes.update_stable_readme!(ctx) }
    workflow.after(:prepare_next) { |ctx| notes.update_development_readme!(ctx) }
  end
end
