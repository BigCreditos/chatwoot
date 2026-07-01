class EvolutionGo::IncomingMessageService
  include Events::Types

  pattr_initialize [:inbox!, :params!]

  def perform
    return if event_data.blank?

    Rails.configuration.dispatcher.dispatch(PROVIDER_EVENT_RECEIVED, Time.zone.now, inbox: inbox, event: event_type,
                                                                                     payload: event_data)

    case event_type
    when 'messages.upsert'
      process_message
    when 'connection.update'
      process_connection_update
    when 'messages.update'
      process_status_update
    else
      Rails.logger.warn "[EVOLUTION_GO] Unsupported event: #{event_type}"
    end
  end

  private

  def event_type
    params[:event] || params['event']
  end

  def event_data
    params[:data] || params['data']
  end

  def process_message
    messages = event_data[:messages] || event_data['messages']
    return if messages.blank?

    messages.each do |msg|
      next if msg[:key][:fromMe] || msg['key']['fromMe']

      process_single_message(msg)
    end
  end

  def process_single_message(msg)
    remote_jid = msg.dig(:key, :remoteJid) || msg.dig('key', 'remoteJid')
    return if remote_jid.blank?

    sender = remote_jid.split('@').first
    msg_id = msg.dig(:key, :id) || msg.dig('key', 'id')
    timestamp = msg[:messageTimestamp] || msg['messageTimestamp']
    content = msg[:message] || msg['message']
    text = content[:conversation] || content['conversation'] || extract_text_from_content(content)

    normalized = {
      messages: [{
        from: sender,
        id: msg_id,
        timestamp: timestamp.to_s,
        type: text.present? ? 'text' : 'unknown',
        text: text.present? ? { body: text } : nil
      }.compact],
      contacts: [{ wa_id: sender, profile: { name: sender } }]
    }

    process_via_base(normalized)
  end

  def extract_text_from_content(content)
    return if content.blank?

    content[:conversation] || content['conversation'] ||
      content.dig(:extendedTextMessage, :text) || content.dig('extendedTextMessage', 'text')
  end

  def process_via_base(normalized)
    service = Whatsapp::IncomingMessageBaseService.new(inbox: inbox, params: normalized.with_indifferent_access)
    service.perform
  end

  def process_connection_update
    data = event_data
    return if data.blank?

    connection = data[:connection] || data['connection']
    qr = data[:qrcode] || data['qrCode'] || data['qr'] || data.dig('data', 'qrcode')
    inbox.channel.update_provider_connection!({ connection: connection, qr_data_url: qr }.compact)
  end

  def process_status_update
    statuses = event_data[:messages] || event_data['messages']
    return if statuses.blank?

    statuses.each do |status_update|
      next unless status_update[:key] || status_update['key']

      msg_id = status_update.dig(:key, :id) || status_update.dig('key', 'id')
      status = status_update[:status] || status_update['status']
      next if msg_id.blank?

      message = inbox.messages.find_by(source_id: msg_id)
      next if message.blank?

      message.update!(status: map_evolution_status(status))
    end
  end

  def map_evolution_status(status)
    case status.to_s
    when '1' then 'sent'
    when '2' then 'delivered'
    when '3' then 'read'
    else 'sent'
    end
  end
end
