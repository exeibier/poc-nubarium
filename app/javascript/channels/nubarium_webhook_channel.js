import consumer from "channels/consumer"

document.addEventListener("turbo:load", () => {
  const metaTag = document.querySelector('meta[name="session-id"]')
  if (metaTag) {
    const sessionId = metaTag.getAttribute("content")

    consumer.subscriptions.create({ channel: "NubariumWebhookChannel", session_id: sessionId }, {
      connected() {
        console.log("Connected to Nubarium Webhook Channel for session:", sessionId)
      },

      disconnected() {
      },

      received(data) {
        console.log("Received data from webhook:", data)
        const payload = data.data;

        if (data.type === "nss") {
          const loadingDiv = document.getElementById("nss-loading")
          const dataPre = document.getElementById("nss-data")

          if (loadingDiv && dataPre) {
            loadingDiv.style.display = 'none';
            dataPre.style.display = 'block';
            dataPre.textContent = JSON.stringify(payload, null, 2);

            // Update employment loading text since NSS is received
            const empLoadingDiv = document.getElementById("employment-loading")
            if (empLoadingDiv) {
              empLoadingDiv.innerHTML = '<div class="loading-spinner"></div> Fetching Employment Info for NSS ' + payload.nss + '...'
            }
          }

        } else if (data.type === "employment") {
          const loadingDiv = document.getElementById("employment-loading")
          const dataPre = document.getElementById("employment-data")

          if (loadingDiv && dataPre) {
            loadingDiv.style.display = 'none';
            dataPre.style.display = 'block';
            dataPre.textContent = JSON.stringify(payload, null, 2);
          }
        }
      }
    });
  }
})
