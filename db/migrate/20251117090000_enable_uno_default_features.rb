class EnableUnoDefaultFeatures < ActiveRecord::Migration[7.0]
  FEATURES_TO_ENABLE = %w[
    ip_lookup
    disable_branding
    email_continuity_on_api_channel
    custom_reply_email
    custom_reply_domain
    crm_integration
    disable_whatsapp_messaging_window
    channel_whatsapp
    channel_api
    channel_notifica_me
    whatsapp_campaign
    captain_integration
    custom_roles
    sla
  ].freeze

  FEATURES_TO_DISABLE = %w[
    read_message
  ].freeze

  def up
    enable_defaults_in_installation_config
    enable_features_on_existing_accounts
    update_pricing_plan_configs
    GlobalConfig.clear_cache
  end

  def down
    # No-op: não removemos as flags já habilitadas em contas existentes.
  end

  private

  def enable_defaults_in_installation_config
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank? || config.value.blank?

    features = config.value.map do |feature|
      if FEATURES_TO_ENABLE.include?(feature['name'])
        feature.merge('enabled' => true)
      elsif FEATURES_TO_DISABLE.include?(feature['name'])
        feature.merge('enabled' => false)
      else
        feature
      end
    end

    config.value = features
    config.save!
  end

  def enable_features_on_existing_accounts
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        account.enable_features!(*FEATURES_TO_ENABLE)
        account.disable_features!(*FEATURES_TO_DISABLE)
      end
    end
  end

  def update_pricing_plan_configs
    # Set INSTALLATION_PRICING_PLAN to "premium"
    plan_config =
      InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
    plan_config.value = 'premium'
    plan_config.save!

    # Set INSTALLATION_PRICING_PLAN_QUANTITY to 1_000_000
    quantity_config =
      InstallationConfig.find_or_initialize_by(
        name: 'INSTALLATION_PRICING_PLAN_QUANTITY'
      )
    quantity_config.value = 1_000_000
    quantity_config.save!
  end
end
