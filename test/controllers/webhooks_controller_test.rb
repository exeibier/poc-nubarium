require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  test "should get nubarium" do
    get webhooks_nubarium_url
    assert_response :success
  end
end
