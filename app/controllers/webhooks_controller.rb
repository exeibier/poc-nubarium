class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :nubarium ]
  skip_before_action :authenticate_poc, only: [ :nubarium ]

  def nubarium
    payload = params.permit!.to_h

    # We passed "Session-Id" in the custom headers to Nubarium.
    # Nubarium sends back custom headers under the `HTTP_SESSION_ID` or similar depending on their payload structure.
    # According to traces, it seems they might not pass custom headers back in the payload directly if we just append them.
    # However, for this POC, let's try to extract it from the headers or if they wrap it.
    session_id = request.headers["Session-Id"] || request.headers["HTTP_SESSION_ID"]

    # Alternatively, if they don't echo headers, we might need a workaround for the POC
    # Let's fallback to broadcasting to a generic "all" channel if session_id is missing
    channel_name = session_id.present? ? "nubarium_webhook_channel_#{session_id}" : "nubarium_webhook_channel_all"

    Rails.logger.info("=========================================")
    Rails.logger.info("NUBARIUM WEBHOOK RECEIVED (Session: #{session_id}):")
    Rails.logger.info(payload.inspect)
    Rails.logger.info("=========================================")

    # 1. Is this the NSS response?
    if payload["webhook"].present? && payload["webhook"]["nss"].present? && payload["webhook"]["claveMensaje"] == "0"
        nss = payload["webhook"]["nss"]

        # Broadcast NSS result
        ActionCable.server.broadcast(channel_name, { type: "nss", data: payload["webhook"] })

        # We need the CURP to get employment info. It isn't returned in the NSS webhook!
        # For a production app, we would look up the CURP from the DB using the session_id.
        # For this POC, since we don't have a DB, we will use a fallback or cache.
        # To make it work immediately, let's trigger it if we have it, but we might be stuck without a DB.
        # *Workaround*: We actually *don't* have the CURP here. Let's assume we can get it from Rails cache for the POC.

        curp = Rails.cache.read("curp_#{session_id}")
        if curp.present?
            service = NubariumService.new
            webhook_url = webhooks_nubarium_url(host: request.host_with_port, protocol: request.protocol)
            service.get_employment_info(curp, nss, webhook_url, { "Session-Id" => session_id })
        else
            Rails.logger.error("Could not find CURP in cache for session #{session_id}. Cannot fetch Employment Info.")
        end

    # 2. Is this the Employment Info response?
    elsif payload["webhook"].present? && payload["webhook"]["data"].present? && payload["webhook"]["data"]["informacionLaboral"].present? || payload["webhook"]["messageCode"] == 1
        # Broadcast Employment Info result
        ActionCable.server.broadcast(channel_name, { type: "employment", data: payload["webhook"] })
    else
        # Unknown or error payload
        ActionCable.server.broadcast(channel_name, { type: "unknown", data: payload["webhook"] || payload })
    end

    head :ok
  end
end
