class Webhooks::BaileysController < ActionController::API
  before_action :set_channel

  def process_payload
    unless valid_webhook_token?
      Rails.logger.warn("[BAILEYS] Invalid webhook verify token for phone: #{params[:phone_number]}")
      head(:unauthorized) && return
    end

    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  def set_channel
    @channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number], provider: 'baileys')
    head(:not_found) unless @channel
  end

  def valid_webhook_token?
    params[:webhookVerifyToken] == @channel.provider_config['webhook_verify_token']
  end
end
