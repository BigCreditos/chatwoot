class AddBaileysFieldsToChannelWhatsapp < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsapp, :qr_data_url, :string
    add_column :channel_whatsapp, :baileys_webhook_secret, :string
    add_index :channel_whatsapp, [:phone_number, :provider], unique: true
  end
end