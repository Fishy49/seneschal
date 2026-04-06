class AddAdminAndInviteToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
    add_column :users, :invite_token, :string
    add_column :users, :invite_accepted_at, :datetime
    add_index :users, :invite_token, unique: true

    reversible do |dir|
      dir.up do
        # Make the first existing user an admin
        execute "UPDATE users SET admin = 1 WHERE id = (SELECT MIN(id) FROM users)"
      end
    end
  end
end
