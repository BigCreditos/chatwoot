class Channel::EvolutionGo < ApplicationRecord
  include Channelable

  self.table_name = 'channel_evolution_go'
  EDITABLE_ATTRS = [:phone_number, { provider_config: {} }].freeze

  validates :phone_number, presence: true, uniqueness: true

  before_validation :ensure_webhook_secret
  before_validation :ensure_provider_config_defaults

  has_one :inbox, as: :channel, dependent: :destroy

  after_create :setup_webhooks
  before_destroy :teardown_webhooks
  before_destroy :disconnect_channel_provider

  def name
    'WhatsApp Evolution Go'
  end

  def provider_service
    EvolutionGo::ProviderService.new(channel: self)
  end

  def provider_connection_data
    provider_connection
  end

  def update_provider_connection!(data)
    update!(provider_connection: data)
  end

  def setup_webhooks
    return if provider_config['webhook_setup_done']

    phone = phone_number.delete_prefix('+')
    config = provider_config
    config['webhook_url'] = "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/evolution_go/#{phone}"
    config['webhook_setup_done'] = true
    update!(provider_config: config)
  end

  def teardown_webhooks
    return unless provider_config['webhook_setup_done']

    config = provider_config
    config['webhook_setup_done'] = false
    update!(provider_config: config)
  end

  def disconnect_channel_provider
    provider_service.disconnect_channel_provider
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] disconnect_channel_provider failed (ignored): #{e.message}")
  end

  def send_message(recipient_id, message)
    provider_service.send_message(recipient_id, message)
  end

  private

  def ensure_webhook_secret
    self.webhook_secret ||= SecureRandom.hex(16)
  end

  def ensure_provider_config_defaults
    self.provider_config ||= {}
    provider_config['provider_url'] ||= ENV.fetch('EVOLUTION_GO_PROVIDER_DEFAULT_URL', nil)
    provider_config['api_key'] ||= ENV.fetch('EVOLUTION_GO_PROVIDER_DEFAULT_API_KEY', nil)
  end
end

Channel::EvolutionGo.prepend_mod_with('Channel::EvolutionGo')
