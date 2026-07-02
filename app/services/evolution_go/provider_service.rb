class EvolutionGo::ProviderService
  class ProviderError < StandardError; end

  pattr_initialize [:channel!]

  def send_message(recipient_id, message)
    phone = recipient_id.delete('+')
    payload = build_message_payload(phone, message)
    endpoint = message.attachments.present? ? 'sendMedia' : 'sendText'
    response = HTTParty.post(
      "#{api_base_path}/message/#{endpoint}",
      headers: api_headers,
      body: payload.to_json,
      timeout: 15
    )
    process_response(response)
  end

  def setup_channel_provider
    response = HTTParty.post(
      "#{api_base_path}/instance/create",
      headers: api_headers,
      body: {
        instanceName: instance_name,
        webhook: channel.inbox.callback_webhook_url,
        webhookByEvents: true,
        events: ['MESSAGES_UPSERT', 'MESSAGES_UPDATE', 'SEND_MESSAGE', 'CONNECTION_UPDATE']
      }.to_json,
      timeout: 15
    )
    raise ProviderError, "API error: #{response.code}" unless response.success?

    qr_response = HTTParty.get(
      "#{api_base_path}/instance/#{instance_name}/qrcode",
      headers: api_headers,
      timeout: 15
    )
    return unless qr_response.success?

    data = qr_response.parsed_response || {}
    qr = data['qrcode'] || data['qr'] || data.dig('data', 'qrcode')
    channel.update_provider_connection!({ connection: 'connecting', qr_data_url: qr }.compact)
    true
  end

  def disconnect_channel_provider
    HTTParty.delete("#{api_base_path}/instance/#{instance_name}", headers: api_headers, timeout: 10)
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] disconnect error (ignored): #{e.message}")
  end

  private

  def api_base_path
    channel.provider_config['provider_url']
  end

  def api_key
    channel.provider_config['api_key']
  end

  def instance_name
    "chatwoot_#{channel.phone_number.delete_prefix('+')}"
  end

  def phone_number
    channel.phone_number.delete_prefix('+')
  end

  def api_headers
    { 'Content-Type' => 'application/json', 'apiKey' => api_key }
  end

  def build_message_payload(phone, message)
    if message.content_type == 'sticker'
      { number: phone, options: { sticker: true, mediaUrl: download_attachment(message) } }
    elsif message.attachments.present?
      att = message.attachments.first
      { number: phone, options: { mediaUrl: download_attachment(message), caption: message.content.presence } }
    elsif message.content_type == 'input_select'
      { number: phone, options: { interactiveType: 'list', title: message.content, **build_interactive_payload(message) } }
    else
      { number: phone, text: message.content }
    end
  end

  def build_interactive_payload(message)
    items = message.content_attributes['items'] || []
    { rows: items.map { |i| { title: i['title'], description: i['description'] } } }
  end

  def download_attachment(message)
    message.attachments.first.download_url
  end

  def process_response(response)
    return response.parsed_response['id'] || response.parsed_response.dig('data', 'id') if response.success?

    Rails.logger.error("[EVOLUTION_GO] API error: #{response.code} #{response.body}")
    nil
  end
end
