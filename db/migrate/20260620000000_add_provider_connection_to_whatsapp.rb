class AddProviderConnectionToWhatsapp < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsapp, :provider_connection, :jsonb, default: {}
    add_index :channel_whatsapp, :provider_connection,
              using: :gin,
              where: "provider IN ('baileys', 'zapi')",
              name: 'index_channel_whatsapp_provider_connection'
  end
end
