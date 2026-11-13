class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name
      t.string :email

      t.timestamps
    end
  end
end
