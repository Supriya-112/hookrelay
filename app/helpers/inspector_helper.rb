module InspectorHelper
  # A delivery's status carries its own colour, so the class comes from the status.
  def status_pill(status)
    tag.span status, class: "pill pill-#{status}"
  end

  # "3 minutes ago" for something that happened, "in 3 minutes" for a retry that
  # is still due — time_ago_in_words gives the same words for both.
  def relative_time(time)
    return tag.span("never", class: "dim") if time.blank?

    words = time_ago_in_words(time)
    tag.time (time.future? ? "in #{words}" : "#{words} ago"), datetime: time.iso8601, title: "#{time.utc} UTC"
  end

  def timestamp(time, format: "%Y-%m-%d %H:%M:%S")
    tag.time time.utc.strftime(format), datetime: time.iso8601, title: "#{time.utc} UTC"
  end

  # Most providers send JSON, and reading it as one line is painful. Anything that
  # doesn't parse is shown exactly as it arrived.
  def payload_body(event)
    body = event.body_text
    return body unless event.content_type.to_s.include?("json")

    JSON.pretty_generate(JSON.parse(body))
  rescue JSON::ParserError
    body
  end
end
