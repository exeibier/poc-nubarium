class VerificationsController < ApplicationController
  def new
  end

  def create
    @results = {}
    service = NubariumService.new

    # Inputs
    email = params[:email]
    phone = params[:phone]

    # New Flow: Base64 Images from SDK Components
    face_image = params[:face_image]
    front_image = params[:front_image]
    back_image = params[:back_image]

    # Infer Document Type based on Back Image presence
    # If back image is present, assume INE. If not, assume Passport.
    document_type = back_image.present? ? "ine" : "passport"

    # Store contact info for display
    @contact_info = { email: email, phone: phone, document_type: document_type }
    @inputs = { face_image: face_image, front_image: front_image, back_image: back_image }

    if face_image.present? && front_image.present?
        # --- NEW FLOW: Component-based Capture ---

        # 1. Face Match / Liveness
        @results[:face_match] = service.face_match(front_image, face_image)

        # 2. OCR (Extract Data)
        ocr_response = service.get_id_ocr(front_image, back_image)
        @results[:ocr] = ocr_response

        if ocr_response["estatus"] != "ERROR"
            # Extract Data
            curp = ocr_response["curp"]
            nombres = ocr_response["nombres"]
            primer_apellido = ocr_response["primerApellido"]
            segundo_apellido = ocr_response["segundoApellido"]

            # 3. CURP Validation
            if curp.present?
                @results[:curp] = service.check_curp(curp)
            end

            # 4. INE Validation (Nominal List) - ONLY IF INE
            if document_type == "ine"
                 @results[:ine_validation] = service.validate_ine(ocr_response)
            else
                 @results[:ine_validation] = { "estatus" => "SKIPPED", "mensaje" => "Passport detected (No back image)" }
            end

            # 5. Blocklist Check
            if nombres.present? && primer_apellido.present?
                @results[:blocklist] = service.check_blocklist(nombres, primer_apellido, segundo_apellido)
            end
        else
            @results[:error] = "OCR Failed: #{ocr_response['mensaje']}"
        end

    else
        @results[:error] = "Missing biometric data."
    end

    render :show
  end

  def show
  end

  def token
    service = NubariumService.new
    token = service.generate_token
    render json: { token: token }
  end
end
