class CreateUserCredentials < ActiveRecord::Migration[8.1]
  # `value` holds an Active Record encrypted payload, which is why it is text
  # rather than string: the ciphertext envelope is considerably longer than
  # the token it wraps.
  def change
    create_table :user_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.text :value, null: false

      t.timestamps
    end

    add_index :user_credentials, [:user_id, :kind], unique: true
  end
end
