class ProcessContactRemindersJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ContactReminder.pending.due.find_each(batch_size: 100) do |reminder|
      process_reminder(reminder)
    end
  end

  private

  def process_reminder(reminder)
    if reminder.send_message? && reminder.message_content.present? && reminder.conversation.present?
      message = reminder.conversation.messages.build(
        content: reminder.message_content,
        account_id: reminder.account_id,
        inbox_id: reminder.conversation.inbox_id,
        message_type: :outgoing,
        sender: reminder.user || reminder.conversation.assignee
      )
      message.save!
    end

    reminder.update!(is_completed: true)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: reminder.account).capture_exception
  end
end
