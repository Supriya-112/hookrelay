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

ActiveRecord::Schema[8.1].define(version: 2026_08_12_173756) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "destination_id", null: false
    t.bigint "event_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_id"], name: "index_deliveries_on_destination_id"
    t.index ["event_id", "destination_id"], name: "index_deliveries_on_event_id_and_destination_id", unique: true
    t.index ["event_id"], name: "index_deliveries_on_event_id"
  end

  create_table "delivery_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "delivery_id", null: false
    t.integer "duration_ms"
    t.string "error"
    t.text "response_body"
    t.integer "status_code"
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_delivery_attempts_on_delivery_id"
  end

  create_table "destinations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["source_id"], name: "index_destinations_on_source_id"
  end

  create_table "events", force: :cascade do |t|
    t.text "body"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.jsonb "headers", default: {}, null: false
    t.string "http_method", null: false
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id"], name: "index_events_on_source_id"
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_sources_on_token", unique: true
  end

  add_foreign_key "deliveries", "destinations"
  add_foreign_key "deliveries", "events"
  add_foreign_key "delivery_attempts", "deliveries"
  add_foreign_key "destinations", "sources"
  add_foreign_key "events", "sources"
end
