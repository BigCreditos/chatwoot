class Webhooks::BaileysController < ActionController::API
  before_action :set_channel

  def process_payload
    unless valid_webhook_token?
      Rails.logger.warn("[BAILEYS] Invalid webhook verify token for phone: #{params[:phone_number]}")
      head(:unauthorized) && return
    end

    Whatsapp::IncomingMessageBaileysService.new(inbox: @channel.inbox, params: params.to_unsafe_hash).perform
    head :ok
  end

  private

  def set_channel
    @channel = Channel::Baileys.find_by(phone_number: params[:phone_number])
    head(:not_found) unless @channel
  end

  def valid_webhook_token?
    params[:webhookVerifyToken] == @channel.webhook_secret
  end
end
