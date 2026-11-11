# frozen_string_literal: true

class ProjectReleaseNotes
  STABLE_PARAGRAPH = /^## Stable Release\n\n[^\n]+$/

  def initialize(readme: 'README.md')
    @readme = readme
  end

  def validate!(_ctx)
    raise ArgumentError, 'expected exactly one stable release paragraph in README.md' unless File.read(@readme).scan(STABLE_PARAGRAPH).one?
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
    File.write(@readme, File.read(@readme).sub(STABLE_PARAGRAPH, "## Stable Release\n\n#{paragraph}"))
  end
end
