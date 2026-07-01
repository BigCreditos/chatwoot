class Webhooks::EvolutionGoController < ActionController::API
  before_action :set_channel

  def process_payload
    EvolutionGo::IncomingMessageService.new(inbox: @channel.inbox, params: params.to_unsafe_hash).perform
    head :ok
  end

  private

  def set_channel
    @channel = Channel::EvolutionGo.find_by(phone_number: params[:phone_number])
    head(:not_found) unless @channel
  end
end
