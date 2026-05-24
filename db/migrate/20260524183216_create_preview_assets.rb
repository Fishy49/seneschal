class CreatePreviewAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :preview_assets do |t|
      t.references :run_step, null: false, foreign_key: { on_delete: :cascade }
      t.references :run,      null: false, foreign_key: { on_delete: :cascade }
      t.string  :kind, null: false
      t.string  :label
      t.string  :original_filename, null: false
      t.string  :content_type
      t.bigint  :byte_size,          null: false, default: 0
      t.string  :storage_path,       null: false

      t.timestamps
    end
  end
end
