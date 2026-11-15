# frozen_string_literal: true

require 'open3'

RSpec.shared_context 'with trusted SSH signatures' do
  before do
    key = File.join(directory, 'release-key')
    _output, error, status = Open3.capture3('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', key)
    raise error unless status.success?

    allowed = File.join(directory, 'allowed-signers')
    File.write(allowed, "fixture@example.com #{File.read("#{key}.pub")}")
    { 'gpg.format' => 'ssh', 'user.signingkey' => key, 'gpg.ssh.allowedSignersFile' => allowed }.each do |name, value|
      _output, error, status = Open3.capture3('git', '-C', checkout, 'config', name, value)
      raise error unless status.success?
    end
  end
end
