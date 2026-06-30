class Macros::ExecutionService < ActionService
  def initialize(macro, conversation, user)
    super(conversation)
    @macro = macro
    @account = macro.account
    @user = user
    Current.user = user
  end

  def perform
    Rails.logger.warn "[MACRO_DEBUG] Starting macro execution. Actions: #{@macro.actions.to_json}"
    @macro.actions.each do |action|
      action = action.with_indifferent_access
      begin
        Rails.logger.warn "[MACRO_DEBUG] Running action: #{action[:action_name]} with params: #{action[:action_params].to_json}"
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        Rails.logger.error "[MACRO_DEBUG] Action #{action[:action_name]} failed with exception: #{e.class}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "macro_event.#{@macro.name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def assign_agent(agent_ids)
    agent_ids = agent_ids.map { |id| id == 'self' ? @user.id : id }
    super(agent_ids)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = ActionController::Parameters.new({ content: message[0], private: true })

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_message(message)
    Rails.logger.warn "[MACRO_DEBUG] send_message called with: #{message.to_json}"
    return if conversation_a_tweet?

    message_content = message[0]
    target_inbox_id = message[1]
    Rails.logger.warn "[MACRO_DEBUG] message_content: #{message_content.inspect}, target_inbox_id: #{target_inbox_id.inspect}"

    if target_inbox_id.present? && target_inbox_id.to_i != @conversation.inbox_id
      target_inbox_id = target_inbox_id.to_i
      Rails.logger.warn "[MACRO_DEBUG] Sending message to target inbox: #{target_inbox_id}"

      target_conversation = @account.conversations.where(
        contact_id: @conversation.contact_id,
        inbox_id: target_inbox_id
      ).order(created_at: :desc).first
      Rails.logger.warn "[MACRO_DEBUG] target_conversation found: #{target_conversation&.id.inspect}"

      if target_conversation.present?
        target_conversation.open! if target_conversation.resolved?
      else
        target_inbox = @account.inboxes.find(target_inbox_id)
        Rails.logger.warn "[MACRO_DEBUG] target_inbox found: #{target_inbox&.name}"

        contact_inbox = ContactInboxBuilder.new(
          contact: @conversation.contact,
          inbox: target_inbox
        ).perform
        Rails.logger.warn "[MACRO_DEBUG] contact_inbox resolved: #{contact_inbox&.id.inspect}, source_id: #{contact_inbox&.source_id.inspect}"

        target_conversation = Conversation.create!(
          account_id: @account.id,
          inbox_id: target_inbox_id,
          contact_id: @conversation.contact_id,
          contact_inbox_id: contact_inbox.id,
          status: :open,
          assignee_id: @conversation.assignee_id
        )
        Rails.logger.warn "[MACRO_DEBUG] target_conversation created: #{target_conversation&.id.inspect}"
      end

      params = ActionController::Parameters.new({ content: message_content, private: false })
      mb = Messages::MessageBuilder.new(@user, target_conversation, params)
      mb.perform
      Rails.logger.warn "[MACRO_DEBUG] MessageBuilder performed on target conversation."
    else
      Rails.logger.warn "[MACRO_DEBUG] Sending message to current conversation."
      params = ActionController::Parameters.new({ content: message_content, private: false })
      mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
      mb.perform
      Rails.logger.warn "[MACRO_DEBUG] MessageBuilder performed on current conversation."
    end
  end

  def apply_delay(delay_seconds)
    seconds = delay_seconds[0].to_i
    Kernel.sleep(seconds) if seconds > 0
  end


  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @macro.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: 'macro.executed')
    WebhookJob.perform_later(webhook_url.first, payload)
  end

  def trigger_typebot(params)
    typebot_url = params[0]
    typebot_slug = params[1]

    return if typebot_url.blank? || typebot_slug.blank?

    @conversation.custom_attributes['typebot_url'] = typebot_url
    @conversation.custom_attributes['typebot_id'] = typebot_slug
    @conversation.custom_attributes.delete('typebot_session_id')
    @conversation.assignee_id = nil
    @conversation.status = :pending
    @conversation.save!

    last_message = @conversation.messages.last
    return if last_message.blank?

    struct = Struct.new(:account, :account_id, :id, :app_id, :settings)
    virtual_hook = struct.new(@conversation.account, @conversation.account_id, nil, 'typebot', {
      'typebot_url' => typebot_url,
      'typebot_id' => typebot_slug
    })

    processor = Integrations::Typebot::ProcessorService.new(
      event_name: 'message.created',
      hook: virtual_hook,
      event_data: { message: last_message }
    )

    start_response = processor.send(:start_chat)
    if start_response && start_response['sessionId']
      @conversation.custom_attributes['typebot_session_id'] = start_response['sessionId']
      @conversation.save!

      processor.send(:process_response, last_message, {
        messages: start_response['messages'] || [],
        client_side_actions: start_response['clientSideActions'] || [],
        input: start_response['input']
      })
    end
  end
end
