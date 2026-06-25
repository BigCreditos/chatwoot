class Whatsapp::IncomingMessageWuzapiService < Whatsapp::IncomingMessageBaseService
  include Events::Types

  def perform
    return if processed_params[:type].blank?

    Rails.configuration.dispatcher.dispatch(PROVIDER_EVENT_RECEIVED, Time.zone.now, inbox: inbox, event: processed_params[:type],
                                                                                     payload: processed_params)

    event_type = processed_params[:type].to_s
    if event_type == 'Message'
      process_wuzapi_message
    else
      Rails.logger.warn "Wuzapi unsupported event: #{event_type}"
    end
  end

  private

  def process_wuzapi_message
    event_data = processed_params[:event] || processed_params
    message_data = event_data[:Message] || event_data['Message']
    info = event_data[:Info] || event_data['Info']

    return if message_data.blank?

    remote_jid = message_data.dig(:key, :remoteJid) || message_data.dig('key', 'remoteJid')
    return if remote_jid.blank?

    from_me = message_data.dig(:key, :fromMe) || message_data.dig('key', 'fromMe')
    return if from_me

    sender_phone = remote_jid.split('@').first
    message_id = message_data.dig(:key, :id) || message_data.dig('key', 'id')
    timestamp = message_data[:messageTimestamp] || message_data['messageTimestamp'] || info[:timestamp] || info['timestamp']

    message_content = message_data[:message] || message_data['message'] || message_data
    text = message_content[:conversation] || message_content['conversation'] || message_content.dig(:extendedTextMessage, :text) || message_content.dig('extendedTextMessage', 'text')

    message_type = determine_message_type(message_content)

    normalized_params = {
      messages: [
        {
          from: sender_phone,
          id: message_id,
          timestamp: timestamp.to_s,
          type: message_type,
          text: text ? { body: text } : nil
        }.compact
      ],
      contacts: [
        {
          wa_id: sender_phone,
          profile: { name: sender_phone }
        }
      ]
    }

    process_normalized(normalized_params)
  end

  def determine_message_type(message_content)
    if message_content[:conversation].present? || message_content['conversation'].present?
      'text'
    elsif message_content[:extendedTextMessage].present? || message_content['extendedTextMessage'].present?
      'text'
    elsif message_content[:imageMessage].present? || message_content['imageMessage'].present?
      'image'
    elsif message_content[:audioMessage].present? || message_content['audioMessage'].present?
      'audio'
    elsif message_content[:videoMessage].present? || message_content['videoMessage'].present?
      'video'
    elsif message_content[:documentMessage].present? || message_content['documentMessage'].present?
      'document'
    else
      'text'
    end
  end

  def process_normalized(normalized_params)
    @params = normalized_params.with_indifferent_access
    process_processed_params

    if processed_params.try(:[], :statuses).present?
      process_statuses
    elsif messages_data.present?
      set_message_type
      set_contact
      return unless @contact
      return if @contact.blocked?

      ActiveRecord::Base.transaction do
        set_conversation
        create_messages
      end
    end
  end
end
