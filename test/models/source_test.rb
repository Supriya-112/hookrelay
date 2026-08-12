require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "generates a unique token on create" do
    a = Source.create!(name: "GitHub")
    b = Source.create!(name: "Stripe")

    assert a.token.present?
    assert_not_equal a.token, b.token
  end

  test "destroying a source destroys its events" do
    source = Source.create!(name: "GitHub")
    source.events.create!(http_method: "POST", headers: {}, body: "{}")

    assert_difference -> { Event.count }, -1 do
      source.destroy
    end
  end
end
