class CreateTicketEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :ticket_events do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.integer :kind, null: false, default: 0
      t.text :body
      t.integer :from_status
      t.integer :to_status
      t.timestamps
    end

    add_index :ticket_events, [ :ticket_id, :created_at ]

    # Internal notes were the whole timeline until now, so they become its
    # first entries rather than being left behind in a table of their own.
    execute <<~SQL
      INSERT INTO ticket_events (ticket_id, author_id, kind, body, created_at, updated_at)
      SELECT ticket_id, author_id, 1, body, created_at, updated_at FROM ticket_notes
    SQL

    drop_table :ticket_notes
  end

  def down
    create_table :ticket_notes do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO ticket_notes (ticket_id, author_id, body, created_at, updated_at)
      SELECT ticket_id, author_id, body, created_at, updated_at FROM ticket_events WHERE kind = 1
    SQL

    drop_table :ticket_events
  end
end
