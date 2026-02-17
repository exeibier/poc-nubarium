class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_poc

  private

  def authenticate_poc
    authenticate_or_request_with_http_basic do |username, password|
      username == ENV["POC_USER"] && password == ENV["POC_PASS"]
    end
  end
end
