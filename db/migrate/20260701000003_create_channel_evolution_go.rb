class CreateChannelEvolutionGo < ActiveRecord::Migration[7.0]
  def change
    create_table :channel_evolution_go do |t|
      t.integer :account_id, null: false
      t.string :phone_number, null: false
      t.jsonb :provider_config, default: {}
      t.jsonb :provider_connection, default: {}
      t.string :qr_data_url
      t.string :webhook_secret
      t.timestamps
    end
    add_index :channel_evolution_go, :phone_number, unique: true
  end
end
