class AddReceivesTicketsToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :receives_tickets, :boolean, default: false, null: false

    # Whoever was already running the tracker keeps running it.
    execute "UPDATE users SET receives_tickets = true WHERE admin = true"
  end

  def down
    remove_column :users, :receives_tickets
  end
end
