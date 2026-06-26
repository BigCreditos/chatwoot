require 'rails_helper'

RSpec.describe 'Webhooks::BaileysController', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'baileys', sync_templates: false, validate_provider_config: false) }
  let(:body) { { event: 'messages.upsert', data: { key: 'value' }, webhookVerifyToken: channel.provider_config['webhook_verify_token'] } }

  describe 'POST /webhooks/baileys/{:phone_number}' do
    it 'returns 404 when channel is not found' do
      post '/webhooks/baileys/+9999999999', params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 when webhook verify token is invalid' do
      post "/webhooks/baileys/#{channel.phone_number}",
           params: body.merge(webhookVerifyToken: 'invalid').to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'calls the whatsapp events job with valid payload' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      post "/webhooks/baileys/#{channel.phone_number}", params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:success)
    end
  end
end
