require "net/http"

# Posts a webhook payload to a destination URL and reports the outcome without
# raising: a non-2xx response, a timeout, or a connection failure all come back
# as a Result (with either a status_code or an error set), so the delivery job
# can record every case the same way.
class WebhookClient
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  Result = Struct.new(:status_code, :body, :duration_ms, :error, keyword_init: true) do
    def success?
      status_code.present? && status_code.between?(200, 299)
    end
  end

  def self.post(url, body:, content_type: nil, headers: {})
    new(url).post(body:, content_type:, headers:)
  end

  def initialize(url)
    @url = url
  end

  def post(body:, content_type: nil, headers: {})
    started = monotonic_ms
    uri = URI.parse(@url)

    request = Net::HTTP::Post.new(uri)
    headers.each { |name, value| request[name] = value }
    request["Content-Type"] = content_type if content_type.present?
    request.body = body

    response = http(uri).request(request)
    Result.new(status_code: response.code.to_i, body: response.body, duration_ms: monotonic_ms - started)
  rescue => e
    Result.new(error: "#{e.class}: #{e.message}", duration_ms: monotonic_ms - started)
  end

  private

  def http(uri)
    Net::HTTP.new(uri.host, uri.port).tap do |client|
      client.use_ssl = uri.scheme == "https"
      client.open_timeout = OPEN_TIMEOUT
      client.read_timeout = READ_TIMEOUT
    end
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
