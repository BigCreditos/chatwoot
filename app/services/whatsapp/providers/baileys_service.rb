class Whatsapp::Providers::BaileysService < Whatsapp::Providers::WhatsappCloudService
  def validate_provider_config?
    whatsapp_channel.provider_config['url'].present?
  end

  def api_headers
    {
      'Authorization' => "Bearer #{whatsapp_channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def phone_id_path
    "#{api_base_path}/connections/#{whatsapp_channel.phone_number}"
  end

  def messages_path
    "#{phone_id_path}/send-message"
  end

  def send_template(phone_number, template_info, message)
    template_body = template_body_parameters(template_info)
    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: recipient_type_for(message),
      to: phone_number,
      type: 'template',
      template: template_body
    }
    response = HTTParty.post(messages_path, headers: api_headers, body: request_body.to_json)
    process_response(response, message)
  end

  def send_attachment_message(phone_number, message, attachment, include_caption: true)
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = { 'link': attachment.download_url }
    type_content['caption'] = whatsapp_outgoing_content(message) unless %w[audio sticker].include?(type) || !include_caption
    mention_ids = whatsapp_mention_ids(message)
    type_content['mentions'] = mention_ids if mention_ids.present?
    type_content['filename'] = attachment.file.filename if type == 'document'
    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: recipient_type_for(message),
      context: whatsapp_reply_context(message),
      to: phone_number,
      type: type,
      type.to_s => type_content
    }
    request_body[:mentions] = mention_ids if mention_ids.present?
    response = HTTParty.post(messages_path, headers: api_headers, body: request_body.to_json)
    process_response(response, message)
  end

  def send_sticker_message(phone_number, message)
    sticker_url = message.content_attributes&.[]('sticker_url')
    return if sticker_url.blank?

    response = HTTParty.post(
      messages_path,
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        recipient_type: recipient_type_for(message),
        context: whatsapp_reply_context(message),
        to: phone_number,
        type: 'sticker',
        sticker: { link: sticker_url }
      }.to_json
    )
    process_response(response, message)
  end

  def send_contacts_message(phone_number, message)
    contacts_payload = whatsapp_contacts_payload(message)
    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: recipient_type_for(message),
      context: whatsapp_reply_context(message),
      to: phone_number,
      type: 'contacts',
      contacts: contacts_payload
    }
    response = HTTParty.post(messages_path, headers: api_headers, body: request_body.to_json)
    process_response(response, message)
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)
    response = HTTParty.post(
      messages_path,
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        recipient_type: recipient_type_for(message),
        to: phone_number,
        interactive: payload,
        type: 'interactive'
      }.to_json
    )
    process_response(response, message)
  end
end
