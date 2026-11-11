# frozen_string_literal: true

class ProjectReleaseNotes
  CATEGORIES = %w[Added Changed Deprecated Removed Fixed Security].freeze
  STABLE_PARAGRAPH = /^## Stable Release\n\n[^\n]+$/

  def initialize(changelog: 'CHANGELOG.md', readme: 'README.md')
    @changelog = changelog
    @readme = readme
  end

  def validate!(_ctx)
    raise ArgumentError, 'expected exactly one stable release paragraph in README.md' unless File.read(@readme).scan(STABLE_PARAGRAPH).one?
  end

  def clean_placeholders!(ctx)
    return if ctx.workflow.changelog.released?(ctx.release.version)

    content = File.read(@changelog).sub(/(^## \[Unreleased\]\n)(.*?)(?=^## |\z)/m) do
      heading = Regexp.last_match(1)
      notes = Regexp.last_match(2).gsub(/^\* Your contribution here\.\n/, '')
      notes = notes.gsub(/^### [^\n]+\n\n*(?=### |\z)/, '')
      "#{heading}#{notes.rstrip}\n\n"
    end
    File.write(@changelog, content)
  end

  def update_stable_readme!(ctx)
    write_readme("You're reading the documentation for the stable release of the project, #{ctx.release.version}.")
  end

  def restore_template!(_ctx)
    content = File.read(@changelog)
    empty_section = /^## \[Unreleased\]\n\n(?=## )/
    return unless content.match?(empty_section)

    categories = CATEGORIES.map { |category| "### #{category}\n\n* Your contribution here.\n\n" }.join
    File.write(@changelog, content.sub(empty_section, "## [Unreleased]\n\n#{categories}"))
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
