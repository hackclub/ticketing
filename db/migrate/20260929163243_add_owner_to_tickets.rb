class AddOwnerToTickets < ActiveRecord::Migration[8.1]
  def up
    add_reference :tickets, :owner, foreign_key: { to_table: :users }

    # A ticket belongs to whoever owns the service it was filed under.
    execute <<~SQL
      UPDATE tickets SET owner_id = services.owner_id
      FROM services WHERE services.id = tickets.service_id
    SQL

    change_column_null :tickets, :owner_id, false
  end

  def down
    remove_reference :tickets, :owner
  end
end
