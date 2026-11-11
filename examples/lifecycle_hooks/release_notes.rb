# frozen_string_literal: true

require 'ruby-gem-release/markdown/section'

class ProjectReleaseNotes
  def initialize(readme: 'README.md')
    @readme_section = RubyGemRelease::Markdown::Section.new(path: readme, heading: '## Stable Release')
  end

  def validate!(_ctx)
    @readme_section.validate!
  end

  def update_stable_readme!(ctx)
    write_readme("You're reading the documentation for the stable release of the project, #{ctx.release.version}.")
  end

  def update_development_readme!(ctx)
    release = ctx.release
    write_readme("You're reading the documentation for the next release of the project, which should be #{release.next_version}. " \
                 "The current stable release is #{release.version}.")
  end

  private

  def write_readme(paragraph)
    @readme_section.replace!(paragraph)
  end
end
