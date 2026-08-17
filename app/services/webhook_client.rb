require "net/http"

# Posts a webhook payload to a destination URL and reports the outcome without
# raising: a non-2xx response, a timeout, a connection failure, or a destination
# we refuse to call all come back as a Result (with either a status_code or an
# error set), so the delivery job can record every case the same way.
class WebhookClient
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  SUCCESS_STATUSES = (200..299)

  Result = Struct.new(:status_code, :body, :duration_ms, :error, keyword_init: true) do
    def success?
      SUCCESS_STATUSES.cover?(status_code)
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
    if (reason = DestinationGuard.blocked_reason(@url))
      return Result.new(error: "refused to deliver: #{reason}", duration_ms: monotonic_ms - started)
    end

    uri = URI.parse(@url)
    request = Net::HTTP::Post.new(uri)
    headers.each { |name, value| request[name] = value }
    request["Content-Type"] = content_type if content_type.present?
    request.body = body

    response = http(uri).request(request)
    Result.new(status_code: response.code.to_i, body: readable(response.body), duration_ms: monotonic_ms - started)
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

  # The response is kept so a human can read what the destination said, and the
  # column holding it is text, which Postgres will only accept as valid UTF-8 —
  # so replace whatever isn't rather than losing the attempt to an insert error.
  def readable(body)
    body&.dup&.force_encoding(Encoding::UTF_8)&.scrub
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
