class AddOwnerToServices < ActiveRecord::Migration[8.1]
  def up
    add_reference :services, :owner, foreign_key: { to_table: :users }

    # Everything that exists today is the first admin's.
    owner_id = select_value("SELECT id FROM users WHERE admin = true ORDER BY id LIMIT 1")
    raise "No admin to own the existing services" if owner_id.nil? && select_value("SELECT COUNT(*) FROM services").to_i.positive?

    execute("UPDATE services SET owner_id = #{owner_id.to_i}") if owner_id

    change_column_null :services, :owner_id, false

    # Two people can each have a service called "Other".
    remove_index :services, :name
    add_index :services, [ :owner_id, :name ], unique: true
  end

  def down
    remove_index :services, [ :owner_id, :name ]
    add_index :services, :name, unique: true
    remove_reference :services, :owner
  end
end
