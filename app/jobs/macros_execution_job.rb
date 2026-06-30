class MacrosExecutionJob < ApplicationJob
  queue_as :medium

  def perform(macro, conversation_ids:, user:)
    Rails.logger.info "[MACRO_DEBUG] MacrosExecutionJob started for macro ##{macro.id} conversations=#{conversation_ids}"

    account = macro.account
    conversations = account.conversations.where(display_id: conversation_ids.to_a)

    if conversations.blank?
      Rails.logger.info "[MACRO_DEBUG] No conversations found for ids=#{conversation_ids}"
      return
    end

    conversations.each do |conversation|
      Rails.logger.info "[MACRO_DEBUG] Executing macro on conversation ##{conversation.display_id}"
      ::Macros::ExecutionService.new(macro, conversation, user).perform
    end
  end
end
