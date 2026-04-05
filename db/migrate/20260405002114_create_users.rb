class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :otp_secret
      t.boolean :otp_required_for_login, default: false, null: false

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
