class Wuzapi::SendOnWuzapiService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Wuzapi
  end

  def perform_reply
    return if message.message_type == :outgoing && message.source_id&.is_present?

    message_id = channel.send_message(whatsapp_recipient, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def whatsapp_recipient
    return message.conversation.group_source_id if message.conversation.group?

    contact_inbox = message.conversation.contact_inbox
    source_id = contact_inbox.source_id
    return source_id unless uuid_source_id?(source_id)

    contact_inbox.contact.phone_number&.sub('+', '').presence || contact_inbox.contact.bsuid
  end

  def uuid_source_id?(source_id)
    source_id.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  end
end
