class NubariumWebhookChannel < ApplicationCable::Channel
  def subscribed
    stream_from "nubarium_webhook_channel_#{params[:session_id]}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
