class CreateAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :assessments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.string :employee_email
      t.string :status
      t.jsonb :responses_json

      t.timestamps
    end
  end
end
