# frozen_string_literal: true

module StubAuthentication
  def self.response(body, forbidden: false)
    response = forbidden ? Net::HTTPForbidden.new('1.1', '403', 'Forbidden') : Net::HTTPOK.new('1.1', '200', 'OK')
    response.define_singleton_method(:body) { JSON.generate(body) }
    response
  end

  def self.oidc_http
    Object.new.tap do |http|
      http.define_singleton_method(:request) do |request|
        raise 'Unexpected OIDC request' unless request.is_a?(Net::HTTP::Get) &&
                                               request.path == '/token?audience=rubygems.org' &&
                                               request['Authorization'] == 'Bearer fixture-request-token'

        StubAuthentication.response({ 'value' => 'fixture-oidc-token' })
      end
    end
  end

  def self.exchange(request)
    raise 'Unexpected exchange request' unless request.is_a?(Net::HTTP::Post) &&
                                               request.path == '/api/v1/oidc/trusted_publisher/exchange_token'

    File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'authentication.json'), request.body)
    response({ 'rubygems_api_key' => 'fixture-api-key' }, forbidden: ENV['RELEASE_TEST_AUTHENTICATION_STATUS'] == '403')
  end

  def start(host, *arguments, **options, &block)
    return block.call(StubAuthentication.oidc_http) if host == 'oidc.example.test'
    return super unless host == 'rubygems.org'

    super do |http|
      http.define_singleton_method(:request, &StubAuthentication.method(:exchange))
      block.call(http)
    end
  end
end

Net::HTTP.singleton_class.prepend(StubAuthentication)
