require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "the health check endpoint responds ok" do
    get "/up"
    assert_response :success
  end
end
