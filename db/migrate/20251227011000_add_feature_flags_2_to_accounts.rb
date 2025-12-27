class AddFeatureFlags2ToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :feature_flags_2, :bigint, default: 0, null: false
  end

  def down
    remove_column :accounts, :feature_flags_2
  end
end
