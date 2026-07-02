# frozen_string_literal: true

class Integrations::Typebot::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  private

  def get_response(_session_id, message_content)
    session_id = conversation.custom_attributes['typebot_session_id']
    typebot_messages = []
    client_side_actions = []
    input_data = nil

    if session_id.blank?
      start_response = start_chat
      if start_response && start_response['sessionId']
        session_id = start_response['sessionId']
        conversation.custom_attributes['typebot_session_id'] = session_id
        conversation.save!

        typebot_messages.concat(start_response['messages'] || [])
        client_side_actions.concat(start_response['clientSideActions'] || [])
        input_data = start_response['input']
      end
    end

    if session_id.present? && message_content.present?
      continue_response = continue_chat(session_id, message_content)
      if continue_response
        typebot_messages.concat(continue_response['messages'] || [])
        client_side_actions.concat(continue_response['clientSideActions'] || [])
        input_data = continue_response['input'] || input_data
      end
    end

    {
      messages: typebot_messages,
      client_side_actions: client_side_actions,
      input: input_data
    }
  rescue StandardError => e
    Rails.logger.error "Typebot Error (account-#{hook.account_id}, hook-#{hook.id}): #{e.message}"
    nil
  end

  def process_response(message, response)
    return if response.blank?

    (response[:messages] || []).each_with_index do |typebot_msg, index|
      content_params = generate_content_params(typebot_msg)
      create_conversation(message, content_params) if content_params.present?

      # Sleep para evitar atropelo na fila WhatsApp (exceto na última mensagem)
      sleep(1) if index < (response[:messages] || []).size - 1
    end

    input = response[:input]
    if input.present? && input['type']&.include?('choice') && input['options'].is_a?(Array)
      items = input['options'].map do |option|
        {
          title: option['value'] || option['label'] || option['id'],
          value: option['value'] || option['label'] || option['id']
        }
      end
      if items.present?
        create_conversation(message, {
          content: 'Select an option',
          content_type: 'input_select',
          content_attributes: { items: items }
        })
      end
    end

    should_handoff = false
    (response[:client_side_actions] || []).each do |action|
      should_handoff = true if action['type'] == 'chatwoot'
    end

    process_action(message, 'handoff') if should_handoff
  end

  def create_conversation(message, content_params)
    return if content_params.blank?

    conversation = message.conversation

    # Se tem attachments, constrói message + anexa + save! único (autosave: true)
    if content_params[:attachments].present?
      attachments = content_params.delete(:attachments)
      msg = conversation.messages.build(
        content_params.merge(
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )
      )
      attachments.each { |att| msg.attachments << att }
      msg.save!
    else
      conversation.messages.create!(
        content_params.merge(
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )
      )
    end
  end

  def start_chat
    base_url = hook.settings['typebot_url'].to_s.strip.gsub(/\/$/, '')
    typebot_id = hook.settings['typebot_id'].to_s.strip
    url = "#{base_url}/api/v1/typebots/#{typebot_id}/startChat"

    prefilled_variables = {
      'name' => contact.name,
      'email' => contact.email,
      'phone_number' => contact.phone_number,
      'conversation_id' => conversation.display_id,
      'inbox_id' => conversation.inbox_id
    }.compact

    body = {
      prefilledVariables: prefilled_variables
    }

    response = HTTParty.post(
      url,
      headers: { 'Content-Type' => 'application/json' },
      body: body.to_json
    )

    if response.success?
      response.parsed_response
    else
      Rails.logger.warn "Typebot Start Chat failed: #{response.code} - #{response.body}"
      nil
    end
  end

  def continue_chat(session_id, message_content)
    base_url = hook.settings['typebot_url'].to_s.strip.gsub(/\/$/, '')
    url = "#{base_url}/api/v1/sessions/#{session_id}/continueChat"

    body = {
      message: message_content
    }

    response = HTTParty.post(
      url,
      headers: { 'Content-Type' => 'application/json' },
      body: body.to_json
    )

    if response.success?
      response.parsed_response
    else
      Rails.logger.warn "Typebot Continue Chat failed: #{response.code} - #{response.body}"
      nil
    end
  end

  def generate_content_params(typebot_msg)
    type = typebot_msg['type']
    url = extract_url(typebot_msg)
    text = extract_text(typebot_msg)

    case type
    when 'text'
      { content: text } if text.present?
    when 'image', 'video', 'audio', 'file'
      if url.present?
        process_typebot_media(type, url, text)
      else
        { content: text } if text.present?
      end
    else
      if url.present?
        { content: "[Attachment](#{url})" }
      else
        { content: text } if text.present?
      end
    end
  end

  def process_typebot_media(type, url, text)
    # Usa SafeFetch (padrão Chatwoot) com proteção SSRF, timeout e validação de content-type
    SafeFetch.fetch(url) do |result|
      file_type = file_type_from_content_type(result.content_type)

      attachment = Attachment.new(
        account_id: conversation.account_id,
        file_type: file_type
      )
      attachment.file.attach(
        io: result.tempfile,
        filename: result.original_filename,
        content_type: result.content_type
      )

      content = text.present? ? text : format_typebot_media_message(type, url)
      { content: content, attachments: [attachment] }
    end
  rescue => e
    Rails.logger.warn "Typebot Media Download Failed (account-#{conversation.account_id}): #{e.message}"
    { content: format_typebot_media_message(type, url) }
  end

  def file_type_from_content_type(content_type)
    case content_type
    when /^image/ then 'image'
    when /^video/ then 'video'
    when /^audio/ then 'audio'
    when /^application\/pdf/ then 'file'
    else 'file'
    end
  end

  def format_typebot_media_message(type, url)
    case type
    when 'image' then "![Image](#{url})"
    when 'video' then "[Video](#{url})"
    when 'audio' then "[Audio](#{url})"
    else "[Attachment](#{url})"
    end
  end

  def extract_text(message)
    if message['content'].is_a?(Hash)
      message['content']['html'] || message['content']['text']
    elsif message['content'].is_a?(String)
      message['content']
    else
      message['text']
    end
  end

  def extract_url(message)
    if message['content'].is_a?(Hash)
      message['content']['url']
    elsif message['content'].is_a?(String)
      message['content']
    else
      message['url']
    end
  end

  def contact
    @contact ||= conversation.contact
  end
end