class Attachments::EnsureAvailabilityJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 3

  def perform(message_id)
    message = Message.find(message_id)
    return if message.attachments.blank?

    attempts = attachment_availability_attempts
    base_delay = attachment_availability_base_delay
    max_delay = [base_delay * 8, base_delay].max

    delay = base_delay
    all_available = false

    attempts.times do
      all_available = message.attachments.all? do |attachment|
        blob = attachment.file&.blob
        blob.present? && blob.service.exist?(blob.key)
      end
      break if all_available

      sleep(delay)
      delay = [delay * 2, max_delay].min
    end

    if all_available && message.progress?
      message.update!(status: :sent)
    elsif !all_available
      Rails.logger.warn("Attachments not available for message #{message_id} after #{attempts} attempts")
    end
  end

  private

  def attachment_availability_attempts
    attempts = ENV.fetch('ATTACHMENT_AVAILABILITY_ATTEMPTS', 5).to_i
    attempts.positive? ? attempts : 5
  end

  def attachment_availability_base_delay
    delay = ENV.fetch('ATTACHMENT_AVAILABILITY_BASE_DELAY', 0.5).to_f
    delay.positive? ? delay : 0.5
  end
end
