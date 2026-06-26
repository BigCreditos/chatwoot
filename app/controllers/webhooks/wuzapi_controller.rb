class Webhooks::WuzapiController < ActionController::API
  before_action :set_channel

  def process_payload
    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  def set_channel
    @channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number], provider: 'wuzapi')
    head(:not_found) unless @channel
  end
end
