class AddBaileysFieldsToChannelWhatsapps < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsapps, :qr_data_url, :string
    add_column :channel_whatsapps, :baileys_webhook_secret, :string
    add_index :channel_whatsapps, [:phone_number, :provider], unique: true
  end
end