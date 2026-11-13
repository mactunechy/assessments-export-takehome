class CreateCompanyAdmins < ActiveRecord::Migration[8.1]
  def change
    create_table :company_admins do |t|
      t.references :company, null: false, foreign_key: true
      t.string :email

      t.timestamps
    end
  end
end
