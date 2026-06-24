# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  provider_connection            :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number  (phone_number) UNIQUE
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud unoapi baileys zapi].freeze
  REACTION_SUPPORTED_PROVIDERS = %w[whatsapp_cloud baileys zapi].freeze
  NEW_CHAT_CAP_KEYS = %w[capping_status ote_status mv_status total_quota used_quota cycle_start_timestamp cycle_end_timestamp].freeze

  before_validation :ensure_unoapi_group_conversation_schema_default
  before_validation :ensure_webhook_verify_token
  before_validation :ensure_provider_config_defaults

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  has_one :inbox, as: :channel, dependent: :destroy

  after_create :sync_templates
  before_destroy :teardown_webhooks
  before_destroy :disconnect_channel_provider, if: -> { provider_service.respond_to?(:disconnect_channel_provider) }
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?
  after_update_commit :enqueue_group_conversation_backfill, if: :should_backfill_group_conversations?

  def name
    'Whatsapp'
  end

  def supports_reactions?
    REACTION_SUPPORTED_PROVIDERS.include?(provider)
  end

  def provider_service
    case provider
    when 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    when 'unoapi'
      Whatsapp::Providers::UnoapiService.new(whatsapp_channel: self)
    when 'baileys'
      Whatsapp::Providers::WhatsappBaileysService.new(whatsapp_channel: self)
    when 'zapi'
      Whatsapp::Providers::WhatsappZapiService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def messaging_window_enabled?
    provider_config['url'] == 'https://graph.facebook.com'
  end

  def use_internal_host?
    provider == 'baileys' && ENV.fetch('BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL', false)
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def update_provider_connection!(provider_connection)
    provider_connection ||= {}
    normalized = provider_connection.deep_stringify_keys
    return if normalized == self.provider_connection

    assign_attributes(provider_connection: normalized)
    Inbox.no_touching { save!(validate: false) }
    broadcast_provider_connection_updated
  end

  def update_reachout_time_lock!(reachout_time_lock)
    return if reachout_time_lock.nil?

    with_lock do
      current_conn = provider_connection || {}
      update_provider_connection!(current_conn.merge('reachout_time_lock' => reachout_time_lock.deep_stringify_keys))
    end
  end

  def update_new_chat_cap!(new_chat_cap)
    return if new_chat_cap.nil?

    normalized = new_chat_cap.to_h.deep_stringify_keys.slice(*NEW_CHAT_CAP_KEYS)
    with_lock do
      current_conn = provider_connection || {}
      update_provider_connection!(current_conn.merge('new_chat_cap' => normalized))
    end
  end

  def provider_connection_data
    current_conn = provider_connection || {}
    data = { connection: current_conn['connection'] }
    data[:reachout_time_lock] = current_conn['reachout_time_lock'] if current_conn['reachout_time_lock'].present?
    data[:new_chat_cap] = current_conn['new_chat_cap'] if current_conn['new_chat_cap'].present?
    if Current.account_user&.administrator?
      data[:qr_data_url] = current_conn['qr_data_url']
      data[:error] = current_conn['error']
    end
    data
  end

  def received_messages(messages, conversation)
    return unless provider_service.respond_to?(:received_messages)

    recipient_id = conversation.contact.identifier || conversation.contact.phone_number
    provider_service.received_messages(recipient_id, messages)
  end

  def disconnect_channel_provider
    provider_service.disconnect_channel_provider
  rescue StandardError => e
    Rails.logger.error "Failed to disconnect channel provider: #{e.message}"
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
  def convert_provider!(new_provider:, new_provider_config:)
    # Serialize concurrent conversions of the same inbox. Without the lock,
    # two admin requests could both pass pre-validation, race the disconnect
    # and save, and leave webhooks/templates mismatched with the persisted
    # provider. `with_lock` issues SELECT FOR UPDATE and wraps the block in
    # a transaction; the loser waits until the winner commits.
    with_lock do
      previous_provider = provider
      previous_provider_config = provider_config.deep_dup
      normalized_new_config = new_provider_config || {}

      if new_provider == previous_provider
        errors.add(:provider, 'must be different from the current provider')
        raise ActiveRecord::RecordInvalid, self
      end

      # Pre-validate the new config without persisting, so we never terminate
      # the current provider session for a known-bad target config.
      assign_attributes(provider: new_provider, provider_config: normalized_new_config)
      unless valid?
        assign_attributes(provider: previous_provider, provider_config: previous_provider_config)
        raise ActiveRecord::RecordInvalid, self
      end
      # Snapshot provider_config AFTER valid? so we keep any fields populated
      # by before_validation callbacks (e.g. ensure_webhook_verify_token). The
      # final persist uses save!(validate: false), so we must not rely on a
      # second validation pass to replay those callbacks.
      validated_new_config = provider_config.deep_dup

      # Validation passed. Restore the old state briefly so the disconnect
      # call talks to the correct (old) endpoint, then reapply and persist
      # the new state. We call the service directly so a failed disconnect
      # propagates and aborts the conversion instead of silently leaving the
      # old session alive while the inbox points at the new provider.
      assign_attributes(provider: previous_provider, provider_config: previous_provider_config)
      # When converting away from whatsapp_cloud, mirror the destroy-time
      # cleanup so the Meta webhook subscription is torn down (embedded_signup
      # source); manual-setup channels follow the same no-op behavior as on
      # destruction. A teardown failure on a best-effort cleanup should not
      # abort the swap.
      if previous_provider == 'whatsapp_cloud'
        begin
          teardown_webhooks
        rescue StandardError => e
          Rails.logger.error "[WHATSAPP] Pre-conversion webhook teardown failed: #{e.message}"
        ensure
          # Reset the destroy-time guard so a later destroy! or subsequent
          # conversion on the same instance doesn't skip webhook removal.
          @webhook_teardown_initiated = false
        end
      end
      provider_service.disconnect_channel_provider if provider_service.respond_to?(:disconnect_channel_provider)

      assign_attributes(
        provider: new_provider,
        provider_config: validated_new_config,
        provider_connection: {},
        message_templates: {},
        message_templates_last_updated: nil
      )
      # Skip revalidation: the pre-flight valid? above is authoritative. A
      # second validate_provider_config? call here would re-hit the external
      # API and a transient failure could roll back the transaction after we
      # already disconnected the old session.
      save!(validate: false)

      setup_webhooks if should_auto_setup_webhooks?

      begin
        sync_templates
      rescue StandardError => e
        # Some provider sync_templates implementations stamp
        # `message_templates_last_updated` before the remote fetch. If the
        # fetch blows up, reset both columns so the inbox doesn't look
        # synced with zero templates and the scheduler will retry.
        update_columns(message_templates: {}, message_templates_last_updated: nil) # rubocop:disable Rails/SkipsModelValidations
        Rails.logger.error "[WHATSAPP] Post-conversion template sync failed: #{e.message}"
      end
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength

  def sync_group(conversation, soft: false)
    return unless provider_service.respond_to?(:sync_group)

    provider_service.sync_group(conversation, soft: soft)
  end

  def allow_group_creation?
    provider_service.respond_to?(:allow_group_creation?) && provider_service.allow_group_creation?
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :send_reaction, to: :provider_service
  delegate :send_message_edit, to: :provider_service
  delegate :send_message_update, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service
  delegate :message_path, to: :provider_service
  delegate :message_update_payload, to: :provider_service
  delegate :message_update_http_method, to: :provider_service

  delegate :setup_channel_provider, to: :provider_service
  delegate :presence_subscribe, to: :provider_service
  delegate :create_group, to: :provider_service
  delegate :update_group_subject, to: :provider_service
  delegate :update_group_description, to: :provider_service
  delegate :update_group_picture, to: :provider_service
  delegate :update_group_participants, to: :provider_service
  delegate :group_invite_code, to: :provider_service
  delegate :revoke_group_invite, to: :provider_service
  delegate :group_join_requests, to: :provider_service
  delegate :handle_group_join_requests, to: :provider_service
  delegate :group_leave, to: :provider_service
  delegate :group_setting_update, to: :provider_service
  delegate :group_join_approval_mode, to: :provider_service
  delegate :group_member_add_mode, to: :provider_service

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def broadcast_provider_connection_updated
    return if inbox.blank?

    Rails.configuration.dispatcher.sync_dispatcher.dispatch(
      Events::Types::INBOX_PROVIDER_CONNECTION_UPDATED, Time.zone.now,
      inbox: inbox, provider_connection: provider_connection
    )
  end

  def ensure_webhook_verify_token
    return unless %w[whatsapp_cloud unoapi baileys zapi].include?(provider)

    self.provider_config ||= {}
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16)
  end

  def ensure_provider_config_defaults
    return unless %w[baileys zapi].include?(provider)

    self.provider_config ||= {}
    provider_config['provider_url'] ||= ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', nil)
    provider_config['api_key'] ||= ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)
  end

  def ensure_unoapi_group_conversation_schema_default
    return unless provider == 'unoapi'

    self.provider_config ||= {}
    provider_config['use_group_conversation_schema'] = true unless provider_config.key?('use_group_conversation_schema')
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  rescue HTTParty::Error => e
    errors.add(:provider_config, e.message)
  rescue SocketError, Errno::ECONNREFUSED
    errors.add(:provider_config, 'Connection refused, verify API URL')
  end

  def perform_webhook_setup
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end

  def should_backfill_group_conversations?
    return false unless provider == 'unoapi'
    return false unless saved_change_to_provider_config?

    old_config, new_config = saved_change_to_provider_config
    old_value = ActiveModel::Type::Boolean.new.cast(old_config&.dig('use_group_conversation_schema'))
    new_value = ActiveModel::Type::Boolean.new.cast(new_config&.dig('use_group_conversation_schema'))

    !old_value && new_value
  end

  def enqueue_group_conversation_backfill
    return if inbox.blank?

    Whatsapp::GroupConversationBackfillJob.perform_later(inbox.id)
    Rails.logger.info("[WHATSAPP][GROUP] backfill enqueued inbox_id=#{inbox.id}")
  end
end
