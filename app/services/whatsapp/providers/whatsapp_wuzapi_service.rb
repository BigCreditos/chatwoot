class Whatsapp::Providers::WhatsappWuzapiService < Whatsapp::Providers::BaseService
  class ProviderUnavailableError < StandardError; end
  class ProviderConfigError < StandardError; end

  def send_template(_phone_number, _template_info); end

  def sync_templates; end

  def setup_channel_provider
    if provider_url.blank?
      raise ProviderConfigError, 'Wuzapi provider URL is not configured. Set BAILEYS_PROVIDER_DEFAULT_URL or configure provider_url in the channel settings.'
    end
    if admin_token.blank?
      raise ProviderConfigError, 'Wuzapi admin token is not configured. Set WUZAPI_ADMIN_TOKEN or configure admin_token in the channel settings.'
    end

    create_wuzapi_user
    connect_session
    fetch_qr_code
    true
  end

  def disconnect_channel_provider
    response = HTTParty.post(
      "#{provider_url}/session/logout",
      headers: api_headers,
      timeout: 10
    )
    Rails.logger.warn("[WHATSAPP][WUZAPI] disconnect_channel_provider non-success status=#{response.code}") unless response.success?

    wuzapi_user_id = whatsapp_channel.provider_config['wuzapi_user_id']
    if wuzapi_user_id.present? && admin_token.present?
      HTTParty.delete(
        "#{provider_url}/admin/users/#{wuzapi_user_id}",
        headers: admin_headers,
        timeout: 10
      )
    end
    true
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][WUZAPI] disconnect_channel_provider failed (ignored): #{e.message}")
    true
  end

  def send_message(recipient_id, message)
    phone = recipient_id.delete('+')

    if message.content_attributes[:is_reaction]
      send_reaction_message(phone, message)
    elsif message.attachments.present?
      send_attachment_message(phone, message)
    elsif message.outgoing_content.present?
      send_text_message(phone, message)
    else
      message.update!(is_unsupported: true)
      nil
    end
  end

  def send_reaction(phone_number, message_id, emoji)
    response = HTTParty.post(
      "#{provider_url}/chat/react",
      headers: api_headers,
      body: {
        phone: phone_number.delete('+'),
        messageId: message_id,
        reaction: emoji
      }.to_json,
      timeout: 10
    )
    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response
  end

  def validate_provider_config?
    response = HTTParty.get(
      "#{provider_url}/session/status",
      headers: api_headers
    )
    process_response(response)
  end

  def toggle_typing_status(typing_status, recipient_id:, **)
    status_map = {
      Events::Types::CONVERSATION_TYPING_ON => 'composing',
      Events::Types::CONVERSATION_RECORDING => 'recording',
      Events::Types::CONVERSATION_TYPING_OFF => 'paused'
    }

    response = HTTParty.post(
      "#{provider_url}/chat/presence",
      headers: api_headers,
      body: {
        phone: recipient_id.delete('+'),
        status: status_map[typing_status]
      }.to_json,
      timeout: 10
    )
    raise ProviderUnavailableError unless process_response(response)
    true
  end

  def read_messages(messages, recipient_id:, **)
    phone = recipient_id.delete('+')

    messages.each do |message|
      next if message.source_id.blank?

      response = HTTParty.post(
        "#{provider_url}/chat/markread",
        headers: api_headers,
        body: {
          phone: phone,
          messageId: message.source_id
        }.to_json,
        timeout: 10
      )
      process_response(response)
    end
    true
  end

  def delete_message(recipient_id, message)
    return false if recipient_id.blank?

    phone = recipient_id.delete('+')

    response = HTTParty.delete(
      "#{provider_url}/chat/send/text",
      headers: api_headers,
      body: {
        phone: phone,
        messageId: message.source_id
      }.to_json,
      timeout: 10
    )
    raise ProviderUnavailableError unless process_response(response)
    true
  end

  def api_headers
    { 'Authorization' => api_key, 'Content-Type' => 'application/json' }
  end

  private

  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || DEFAULT_URL
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || DEFAULT_API_KEY
  end

  def admin_token
    whatsapp_channel.provider_config['admin_token'].presence || ENV.fetch('WUZAPI_ADMIN_TOKEN', nil)
  end

  def admin_headers
    { 'Authorization' => admin_token, 'Content-Type' => 'application/json' }
  end

  def DEFAULT_URL
    ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', nil)
  end

  def DEFAULT_API_KEY
    ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)
  end

  def create_wuzapi_user
    response = HTTParty.post(
      "#{provider_url}/admin/users",
      headers: admin_headers,
      body: {
        webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
        events: ['Message']
      }.to_json,
      timeout: 10
    )

    raise ProviderUnavailableError unless process_response(response)

    parsed = response.parsed_response || {}
    user_id = parsed['user_id'] || parsed.dig('data', 'user_id')
    user_token = parsed['token'] || parsed.dig('data', 'token')

    if user_id.present? && user_token.present?
      config = whatsapp_channel.provider_config.merge(
        'wuzapi_user_id' => user_id,
        'api_key' => user_token
      )
      whatsapp_channel.update!(provider_config: config)
    end
  end

  def connect_session
    response = HTTParty.post(
      "#{provider_url}/session/connect",
      headers: api_headers,
      body: {
        Subscribe: ['Message']
      }.to_json,
      timeout: 10
    )

    raise ProviderUnavailableError unless process_response(response)
  end

  def fetch_qr_code
    response = HTTParty.get(
      "#{provider_url}/session/qr",
      headers: api_headers,
      timeout: 30
    )

    if response.success? && response.parsed_response.present?
      qr_code = response.parsed_response['qr'] || response.parsed_response['qrcode'] || response.parsed_response.dig('data', 'qr')
      if qr_code.present?
        whatsapp_channel.update_provider_connection!(
          connection: 'connecting',
          qr_data_url: qr_code
        )
      else
        whatsapp_channel.update_provider_connection!(connection: 'connecting')
      end
    else
      whatsapp_channel.update_provider_connection!(connection: 'connecting')
    end
  end

  def send_text_message(phone, message)
    response = HTTParty.post(
      "#{provider_url}/chat/send/text",
      headers: api_headers,
      body: {
        phone: phone,
        message: message.outgoing_content
      }.compact.to_json,
      timeout: 60
    )

    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response&.dig('messageId')
  end

  def send_attachment_message(phone, message)
    attachment = message.attachments.first
    base64_data = attachment_to_base64(attachment)
    buffer = "data:#{attachment.file.content_type};base64,#{base64_data}"

    case attachment.file_type
    when 'image'
      send_image_message(phone, message, buffer)
    when 'audio'
      send_audio_message(phone, message, buffer)
    when 'file'
      send_document_message(phone, message, attachment, buffer)
    when 'video'
      send_video_message(phone, message, buffer)
    end
  end

  def send_image_message(phone, message, buffer)
    response = HTTParty.post(
      "#{provider_url}/chat/send/image",
      headers: api_headers,
      body: {
        phone: phone,
        image: buffer,
        caption: message.outgoing_content
      }.compact.to_json,
      timeout: 120
    )
    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response&.dig('messageId')
  end

  def send_audio_message(phone, _message, buffer)
    response = HTTParty.post(
      "#{provider_url}/chat/send/audio",
      headers: api_headers,
      body: {
        phone: phone,
        audio: buffer
      }.compact.to_json,
      timeout: 120
    )
    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response&.dig('messageId')
  end

  def send_document_message(phone, message, attachment, buffer)
    response = HTTParty.post(
      "#{provider_url}/chat/send/document",
      headers: api_headers,
      body: {
        phone: phone,
        document: buffer,
        fileName: attachment.file.filename.to_s,
        caption: message.outgoing_content
      }.compact.to_json,
      timeout: 120
    )
    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response&.dig('messageId')
  end

  def send_video_message(phone, message, buffer)
    response = HTTParty.post(
      "#{provider_url}/chat/send/video",
      headers: api_headers,
      body: {
        phone: phone,
        video: buffer,
        caption: message.outgoing_content
      }.compact.to_json,
      timeout: 120
    )
    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response&.dig('messageId')
  end

  def send_reaction_message(phone, message)
    response = HTTParty.post(
      "#{provider_url}/chat/react",
      headers: api_headers,
      body: {
        phone: phone,
        messageId: message.in_reply_to_external_id,
        reaction: message.outgoing_content
      }.compact.to_json,
      timeout: 60
    )
    raise ProviderUnavailableError unless process_response(response)
    response.parsed_response&.dig('messageId')
  end

  def process_response(response)
    Rails.logger.error response.body unless response.success?
    response.success?
  end
end
