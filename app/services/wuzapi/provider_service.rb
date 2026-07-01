class Wuzapi::ProviderService
  class ProviderError < StandardError; end

  pattr_initialize [:channel!]

  def send_message(recipient_id, message)
    phone = recipient_id.delete('+')
    payload = build_message_payload(phone, message)
    response = HTTParty.post(
      "#{api_base_path}/session/send-message",
      headers: api_headers,
      body: payload.to_json,
      timeout: 15
    )
    process_response(response)
  end

  def setup_channel_provider
    create_wuzapi_user
    start_session
  end

  def disconnect_channel_provider
    HTTParty.post("#{api_base_path}/session/logout", headers: api_headers, timeout: 10)
    user_id = channel.provider_config['wuzapi_user_id']
    return unless user_id.present? && admin_token.present?

    HTTParty.delete("#{api_base_path}/admin/users/#{user_id}", headers: admin_headers, timeout: 10)
  rescue StandardError => e
    Rails.logger.warn("[WUZAPI] disconnect error (ignored): #{e.message}")
  end

  private

  def api_base_path
    channel.provider_config['provider_url']
  end

  def token
    channel.provider_config['admin_token']
  end

  def admin_token
    channel.provider_config['admin_token']
  end

  def wuzapi_token
    channel.provider_config['wuzapi_token']
  end

  def phone_number
    channel.phone_number.delete_prefix('+')
  end

  def api_headers
    headers = { 'Content-Type' => 'application/json' }
    headers['Authorization'] = "Bearer #{wuzapi_token}" if wuzapi_token.present?
    headers
  end

  def admin_headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{admin_token}" }
  end

  def create_wuzapi_user
    return if channel.provider_config['wuzapi_user_id'].present?

    response = HTTParty.post(
      "#{api_base_path}/admin/users",
      headers: admin_headers,
      body: {
        name: "chatwoot_#{phone_number}",
        token: SecureRandom.hex(16),
        webhook: channel.inbox.callback_webhook_url,
        events: 'Message,Presence,ReadReceipt'
      }.to_json,
      timeout: 10
    )
    return unless response.success?

    data = response.parsed_response || {}
    config = channel.provider_config
    config['wuzapi_user_id'] = data['id'] || data['_id']
    config['wuzapi_token'] = data['token']
    channel.update!(provider_config: config)
  end

  def start_session
    response = HTTParty.post(
      "#{api_base_path}/session/start",
      headers: api_headers,
      timeout: 15
    )
    return unless response.success?

    data = response.parsed_response || {}
    qr = data.dig('data', 'qr') || data['qr'] || data['qrCode']
    channel.update_provider_connection!({ connection: 'connecting', qr_data_url: qr }.compact)
  end

  def build_message_payload(phone, message)
    if message.content_type == 'sticker'
      { phone: phone, type: 'sticker', media_url: download_attachment(message) }
    elsif message.attachments.present?
      att = message.attachments.first
      { phone: phone, type: att.file_type, media_url: download_attachment(message) }
    else
      { phone: phone, type: 'text', text: message.content }
    end
  end

  def download_attachment(message)
    message.attachments.first.download_url
  end

  def process_response(response)
    return response.parsed_response['id'] || response.parsed_response.dig('data', 'id') if response.success?

    Rails.logger.error("[WUZAPI] API error: #{response.code} #{response.body}")
    nil
  end
end
