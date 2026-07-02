class Baileys::ProviderService
  class ProviderError < StandardError; end

  pattr_initialize [:channel!]

  def send_message(recipient_id, message)
    phone = recipient_id.delete('+')
    payload = build_message_payload(phone, message)
    response = HTTParty.post(
      "#{api_base_path}/connections/#{phone_number}/send-message",
      headers: api_headers,
      body: payload.to_json,
      timeout: 15
    )
    process_response(response)
  end

  def setup_channel_provider
    response = HTTParty.post(
      "#{api_base_path}/connections/#{phone_number}",
      headers: api_headers,
      body: {
        webhookUrl: channel.inbox.callback_webhook_url,
        webhookVerifyToken: channel.webhook_secret
      }.compact.to_json,
      timeout: 15
    )
    raise ProviderError, "API error: #{response.code}" unless response.success?

    data = response.parsed_response || {}
    qr = data['qr'] || data['qrCode'] || data.dig('data', 'qr') || data.dig('data', 'qrCode')
    channel.update_provider_connection!({ connection: 'connecting', qr_data_url: qr }.compact)
    true
  end

  def disconnect_channel_provider
    HTTParty.delete("#{api_base_path}/connections/#{phone_number}", headers: api_headers, timeout: 10)
  rescue StandardError => e
    Rails.logger.warn("[BAILEYS] disconnect error (ignored): #{e.message}")
  end

  private

  def api_base_path
    channel.provider_config['provider_url']
  end

  def api_key
    channel.provider_config['api_key']
  end

  def phone_number
    channel.phone_number.delete_prefix('+')
  end

  def api_headers
    { 'Content-Type' => 'application/json', 'x-api-key' => api_key }
  end

  def build_message_payload(phone, message)
    if message.content_type == 'sticker'
      { phone: phone, type: 'sticker', mediaUrl: download_attachment(message) }
    elsif message.attachments.present?
      { phone: phone, type: message.attachments.first.file_type, mediaUrl: download_attachment(message) }
    elsif message.content_type == 'input_select'
      { phone: phone, type: 'interactive', interactiveType: 'list', **build_interactive_payload(message) }
    else
      { phone: phone, type: 'text', text: message.content }
    end
  end

  def build_interactive_payload(message)
    items = message.content_attributes['items'] || []
    { title: message.content, rows: items.map { |i| { title: i['title'], description: i['description'] } } }
  end

  def download_attachment(message)
    message.attachments.first.download_url
  end

  def process_response(response)
    return response.parsed_response['id'] || response.parsed_response.dig('data', 'id') if response.success?

    Rails.logger.error("[BAILEYS] API error: #{response.code} #{response.body}")
    nil
  end
end
