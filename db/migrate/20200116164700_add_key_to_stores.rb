class AddKeyToStores < ActiveRecord::Migration[5.2]
  def change
    add_column :stores, :key, :string
    add_index :stores, :key, :unique => true
  end
end
