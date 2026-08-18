module InspectorHelper
  # A delivery's status carries its own colour, so the class comes from the status.
  def status_pill(status)
    tag.span status, class: "pill pill-#{status}"
  end

  def received_at(time)
    return tag.span("never", class: "dim") if time.blank?

    tag.time "#{time_ago_in_words(time)} ago", datetime: time.iso8601, title: time.utc.to_s
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
