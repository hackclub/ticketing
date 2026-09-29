# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_29_163243) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "oauth_clients", force: :cascade do |t|
    t.string "client_id"
    t.string "client_secret_digest"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "redirect_uris", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_oauth_clients_on_client_id", unique: true
  end

  create_table "oauth_grants", force: :cascade do |t|
    t.string "code_challenge"
    t.string "code_digest"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "oauth_client_id", null: false
    t.string "redirect_uri"
    t.string "resource"
    t.string "scope"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["code_digest"], name: "index_oauth_grants_on_code_digest", unique: true
    t.index ["oauth_client_id"], name: "index_oauth_grants_on_oauth_client_id"
    t.index ["user_id"], name: "index_oauth_grants_on_user_id"
  end

  create_table "oauth_tokens", force: :cascade do |t|
    t.string "access_token_digest"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "oauth_client_id", null: false
    t.string "refresh_token_digest"
    t.datetime "revoked_at"
    t.string "scope"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["access_token_digest"], name: "index_oauth_tokens_on_access_token_digest", unique: true
    t.index ["oauth_client_id"], name: "index_oauth_tokens_on_oauth_client_id"
    t.index ["refresh_token_digest"], name: "index_oauth_tokens_on_refresh_token_digest", unique: true
    t.index ["user_id"], name: "index_oauth_tokens_on_user_id"
  end

  create_table "services", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id", "name"], name: "index_services_on_owner_id_and_name", unique: true
    t.index ["owner_id"], name: "index_services_on_owner_id"
  end

  create_table "ticket_blocks", force: :cascade do |t|
    t.bigint "blocked_ticket_id", null: false
    t.bigint "blocker_ticket_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_ticket_id", "blocker_ticket_id"], name: "index_ticket_blocks_on_blocked_ticket_id_and_blocker_ticket_id", unique: true
    t.index ["blocked_ticket_id"], name: "index_ticket_blocks_on_blocked_ticket_id"
    t.index ["blocker_ticket_id"], name: "index_ticket_blocks_on_blocker_ticket_id"
  end

  create_table "ticket_notes", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_ticket_notes_on_author_id"
    t.index ["ticket_id"], name: "index_ticket_notes_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.text "message", null: false
    t.bigint "owner_id", null: false
    t.integer "priority", default: 0, null: false
    t.bigint "service_id", null: false
    t.integer "status", default: 0, null: false
    t.text "status_note"
    t.string "title", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id", null: false
    t.index ["owner_id"], name: "index_tickets_on_owner_id"
    t.index ["priority"], name: "index_tickets_on_priority"
    t.index ["service_id"], name: "index_tickets_on_service_id"
    t.index ["status"], name: "index_tickets_on_status"
    t.index ["topic_id"], name: "index_tickets_on_topic_id"
    t.index ["user_id"], name: "index_tickets_on_user_id"
  end

  create_table "topics", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "name"], name: "index_topics_on_service_id_and_name", unique: true
    t.index ["service_id"], name: "index_topics_on_service_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "api_token_digest"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.boolean "priority_boost", default: false, null: false
    t.boolean "receives_tickets", default: false, null: false
    t.string "slack_id"
    t.string "sub", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token_digest"], name: "index_users_on_api_token_digest", unique: true
    t.index ["sub"], name: "index_users_on_sub", unique: true
  end

  add_foreign_key "oauth_grants", "oauth_clients"
  add_foreign_key "oauth_grants", "users"
  add_foreign_key "oauth_tokens", "oauth_clients"
  add_foreign_key "oauth_tokens", "users"
  add_foreign_key "services", "users", column: "owner_id"
  add_foreign_key "ticket_blocks", "tickets", column: "blocked_ticket_id"
  add_foreign_key "ticket_blocks", "tickets", column: "blocker_ticket_id"
  add_foreign_key "ticket_notes", "tickets"
  add_foreign_key "ticket_notes", "users", column: "author_id"
  add_foreign_key "tickets", "services"
  add_foreign_key "tickets", "topics"
  add_foreign_key "tickets", "users"
  add_foreign_key "tickets", "users", column: "owner_id"
  add_foreign_key "topics", "services"
end
