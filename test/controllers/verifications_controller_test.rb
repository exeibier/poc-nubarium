require "test_helper"

class VerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["POC_USER"] = "testuser"
    ENV["POC_PASS"] = "testpass"
    @auth_headers = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("testuser", "testpass") }
  end

  test "should get new" do
    get new_verification_url, headers: @auth_headers
    assert_response :success
  end

  test "should create verification" do
    post verifications_url, headers: @auth_headers
    assert_response :success
  end
end
