require 'rails_helper'

RSpec.describe 'Webhooks::WuzapiController', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'wuzapi', sync_templates: false, validate_provider_config: false) }
  let(:body) { { type: 'Message', event: { Message: { key: { remoteJid: '+5511999999999@s.whatsapp.net', fromMe: false, id: 'abc123' }, messageTimestamp: 1_234_567, message: { conversation: 'Hello' } }, Info: { timestamp: 1_234_567 } } } }

  describe 'POST /webhooks/wuzapi/{:phone_number}' do
    it 'returns 404 when channel is not found' do
      post '/webhooks/wuzapi/+9999999999', params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:not_found)
    end

    it 'calls the whatsapp events job with valid payload' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      post "/webhooks/wuzapi/#{channel.phone_number}", params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:success)
    end
  end
end
