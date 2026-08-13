require "test_helper"

class DeliveryAttemptTest < ActiveSupport::TestCase
  test "ok? is true only for a 2xx status code" do
    assert DeliveryAttempt.new(status_code: 200).ok?
    assert DeliveryAttempt.new(status_code: 204).ok?
    assert_not DeliveryAttempt.new(status_code: 500).ok?
    assert_not DeliveryAttempt.new(status_code: nil, error: "boom").ok?
  end
end
