# frozen_string_literal: true

require_relative 'signed_tags'

RSpec.shared_examples 'a reviewed release lifecycle' do
  include_context 'with trusted SSH signatures'

  def consumer_rakefile
    <<~RUBY
      require 'ruby-gem-release/workflow/reviewed_ruby_gem'
      require 'ruby-gem-release/changelog/notes'
      require 'ruby-gem-release/package/content_audit'

      provider = RubyGemRelease::ExecutionProvider.current
      audit = RubyGemRelease::Package::ContentAudit.new(expected_files: ['lib/example/version.rb'])
      package = RubyGemRelease::Package::RubyGem.new(directory: provider.directory, audit: audit)
      RubyGemRelease::Workflow::ReviewedRubyGem.new(
        package: package, branches: ['7-2-stable'], provider: provider,
        notes: RubyGemRelease::Changelog::Notes.new,
        success: #{result_callback('success')},
        failure: #{result_callback('failure')}
      ).install_tasks
    RUBY
  end

  before do
    File.write(File.join(checkout, 'CHANGELOG.md'), "# Changelog\n\n## 0.1.0 (2026/11/07)\n\n- Reviewed change.\n")
    run_git('-C', checkout, 'add', '.')
    run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Review release')
    run_git('-C', checkout, 'switch', '--quiet', '-c', '7-2-stable')
    run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'tag', '-s', '-m', 'Reviewed release', 'v0.1.0')
    run_git('-C', checkout, 'push', '--quiet', '-u', 'origin', '7-2-stable', 'refs/tags/v0.1.0')
    environment['GITHUB_REF'] = 'refs/heads/7-2-stable'
    environment['RELEASE_TEST_REVIEWED_SOURCE'] = 'true'
  end

  it 'publishes the signed stable-branch source repeatedly without preparation, tags, pushes, or a development bump' do
    initial = run_git('-C', checkout, 'rev-parse', 'HEAD')
    refs = run_git('-C', checkout, 'show-ref', '--heads', '--tags')
    remote_refs = run_git('--git-dir', remote, 'show-ref')
    2.times do
      configure_inputs
      ['Capture Release Context', 'Validate Release', 'Prepare Release', 'Resolve Prepared Version',
       'Checkpoint Release', 'Publish Release', 'Prepare Next Development Iteration', 'Run Release Success Callback'].each { |name| run_phase(name) }
    end
    expect(run_git('-C', checkout, 'rev-parse', 'HEAD')).to eq(initial)
    expect(run_git('-C', checkout, 'show-ref', '--heads', '--tags')).to eq(refs)
    expect(run_git('--git-dir', remote, 'show-ref')).to eq(remote_refs)
    expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
    expect(JSON.parse(File.read(File.join(directory, 'success.json')))).to eq(['0.1.0', '0.1.0', nil])
    expect(Gem::Package.new(File.join(directory, 'release.gem')).contents).to eq(['lib/example/version.rb'])
    expect(File).to exist(File.join(directory, 'release.bundle'))
    publications = File.readlines(File.join(directory, 'publication.jsonl')).map { |line| JSON.parse(line) }
    expect(publications.count { |command| command.include?('push') }).to eq(1)
    expect(publications.count { |command| command.include?('create') }).to eq(1)
  end
end
