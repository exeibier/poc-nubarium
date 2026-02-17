require "net/http"
require "uri"
require "base64"
require "faraday"
require "json"
require "mini_magick"

class NubariumService
  BASE_URL_API = "https://api.nubarium.com".freeze
  BASE_URL_CURP = "https://curp.nubarium.com".freeze
  BASE_URL_INE = "https://ine.nubarium.com".freeze
  BASE_URL_OCR = "https://ocr.nubarium.com".freeze
  BASE_URL_BIO = "https://biometrics.nubarium.com".freeze
  BASE_URL_SDK = "https://api.sdk.nubarium.com".freeze

  def initialize
    @api_key = ENV["NUBARIUM_API_KEY"]
    @api_secret = ENV["NUBARIUM_API_SECRET"]
    @token = nil
  end

  # --- Authentication ---
  def generate_token
    # POST https://api.sdk.nubarium.com/jwt/v1/generate
    # Header: Authentication "Basic user:password" (Base64 encoded)

    conn = Faraday.new(url: BASE_URL_SDK) do |f|
        f.request :authorization, :basic, @api_key, @api_secret
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    response = conn.post("/jwt/v1/generate") do |req|
      req.body = { expireAfter: 3600 }
    end

    if response.success? && response.body.is_a?(Hash) && response.body["bearer_token"]
        @token = response.body["bearer_token"]
        Rails.logger.info("Nubarium: Token generated successfully.")
        @token
    else
        error_msg = "Nubarium Token Error: Status: #{response.status}, Body: #{response.body}"
        Rails.logger.error(error_msg)
        nil
    end
  end

  def ensure_token
    generate_token unless @token
    @token
  end

  # --- CURP (RENAPO) ---
  def check_curp(curp)
    ensure_token
    # POST https://curp.nubarium.com/renapo/v3/valida_curp
    conn = Faraday.new(url: BASE_URL_CURP) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Checking CURP #{curp}...")
    response = conn.post("/renapo/v3/valida_curp") do |req|
        req.body = { curp: curp }
    end

    log_response("CURP", response)
    ensure_hash_response(response)
  end

  # --- INE Flow ---
  # 1. OCR
  # 2. OCR (Extract Data)
  def get_id_ocr(front_image_base64, back_image_base64 = nil)
    ensure_token
    # POST https://ocr.nubarium.com/ocr/v1/obtener_datos_id
    conn = Faraday.new(url: BASE_URL_OCR) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Getting ID OCR...")

    payload = { id: front_image_base64 }
    payload[:idReverso] = back_image_base64 if back_image_base64.present?

    response = conn.post("/ocr/v1/obtener_datos_id") do |req|
        req.body = payload
    end

    log_response("OCR", response)
    ensure_hash_response(response)
  end

  # 2. Validate against Nominal List
  def validate_ine(ocr_data)
    ensure_token
    # POST https://ine.nubarium.com/ine/v2/valida_ine
    # Using data from OCR response.
    # Logic from docs:
    # CIC mandatory if type D, E, F, G, H
    # identificadorCiudadano mandatory if E, F, G, H
    # OCR mandatory if C, D
    # claveElector mandatory if C
    # numeroEmision mandatory if C

    payload = {}

    # Simple mapping based on what's available in OCR data
    payload[:cic] = ocr_data["cic"] if ocr_data["cic"].present?
    payload[:identificadorCiudadano] = ocr_data["identificadorCiudadano"] if ocr_data["identificadorCiudadano"].present?
    payload[:ocr] = ocr_data["ocr"] if ocr_data["ocr"].present?
    payload[:claveElector] = ocr_data["claveElector"] if ocr_data["claveElector"].present?
    payload[:numeroEmision] = ocr_data["numeroEmision"] if ocr_data["numeroEmision"].present?

    conn = Faraday.new(url: BASE_URL_INE) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Validating INE with OCR data (CIC: #{payload[:cic]})... (SKIPPED)")
    # response = conn.post("/ine/v2/valida_ine") do |req|
    #     req.body = payload
    # end

    # log_response("INE Validation", response)
    # ensure_hash_response(response)
    Rails.logger.info("Nubarium: Validating INE with OCR data (CIC: #{payload[:cic]})...")
    response = conn.post("/ine/v2/valida_ine") do |req|
        req.body = payload
    end

    log_response("INE Validation", response)
    ensure_hash_response(response)
  end

  # 3. Biometrics (Face Match)
  def face_match(front_image_base64, selfie_base64)
    ensure_token
    # POST https://biometrics.nubarium.com/antifraude/reconocimiento_facial
    conn = Faraday.new(url: BASE_URL_BIO) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Performing Face Match for #{front_image_base64.size} bytes vs #{selfie_base64.size} bytes...")
    response = conn.post("/antifraude/reconocimiento_facial") do |req|
        req.body = {
            credencial: front_image_base64,
            captura: selfie_base64,
            tipo: "imagen"
        }
    end

    log_response("Face Match", response)
    ensure_hash_response(response)
  end

  # --- Blocklist ---
  def check_blocklist(first_name, last_name, second_last_name)
    ensure_token
    # POST https://api.nubarium.com/blacklists/v1/consulta
    # Construct "nombreCompleto" or use separate fields.
    # The docs say: "nombreCompleto" (optional) OR "nombres" + "apellidos".

    full_name = "#{first_name} #{last_name} #{second_last_name}".strip

    conn = Faraday.new(url: BASE_URL_API) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Checking Blocklist for #{full_name}...")
    response = conn.post("/blacklists/v1/consulta") do |req|
        req.body = {
            nombreCompleto: full_name,
            similitud: 100
        }
    end

    log_response("Blocklist", response)
    ensure_hash_response(response)
  end

  # Helper to encode file to base64
  # Helper to encode file to base64, converting HEIC/HEIF to JPEG if necessary
  def self.encode_file(file)
    return nil unless file

    # Check if the file is HEIC/HEIF and convert
    original_filename = file.original_filename.downcase
    content_type = file.content_type

    blob = file.read

    if original_filename.end_with?(".heic", ".heif") || content_type == "image/heic" || content_type == "image/heif"
      Rails.logger.info("Nubarium: Converting HEIC image to JPEG...")
      image = MiniMagick::Image.read(blob)
      image.format "jpeg"
      blob = image.to_blob
    end

    Base64.strict_encode64(blob)
  rescue => e
    Rails.logger.error("Nubarium: Image conversion error: #{e.message}")
    # Fallback to original content if conversion fails
    Base64.strict_encode64(file.read)
  end

  # --- SDK Integration ---
  def get_video_execution(execution_id)
    ensure_token
    # GET https://api.sdk.nubarium.com/video/v1/executions/:execution_id
    conn = Faraday.new(url: BASE_URL_SDK) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Getting Video Execution #{execution_id}...")
    response = conn.get("/video/v1/executions/#{execution_id}")

    log_response("Video Execution", response)
    ensure_hash_response(response)
  end

  def get_video_resource(execution_id, resource_type)
    ensure_token
    # GET https://api.sdk.nubarium.com/video/v1/executions/:execution_id/content/:resource_type
    conn = Faraday.new(url: BASE_URL_SDK) do |f|
        f.request :authorization, "Bearer", @token
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
    end

    Rails.logger.info("Nubarium: Getting Video Resource #{resource_type} for #{execution_id}...")
    response = conn.get("/video/v1/executions/#{execution_id}/content/#{resource_type}")

    # log_response("Video Resource #{resource_type}", response) # Don't log full body if base64
    if response.success?
      response.body
    else
      Rails.logger.error("Nubarium Video Resource Failed: #{response.status}")
      nil
    end
  end

  private

  def log_response(service_name, response)
    if response.success?
      Rails.logger.info("Nubarium #{service_name} Success: #{response.status}")
      # Rails.logger.debug("Nubarium #{service_name} Body: #{response.body}")
    else
      Rails.logger.error("Nubarium #{service_name} Failed: #{response.status}")
      Rails.logger.error("Nubarium #{service_name} Body: #{response.body}")
    end
  end

  def ensure_hash_response(response)
    if response.body.is_a?(Hash)
      response.body
    else
      { "estatus" => "ERROR", "mensaje" => "Invalid response from Nubarium: #{response.status} - #{response.body}" }
    end
  end
end
