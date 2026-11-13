class AddCompanyIdIdIndexToAssessments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :assessments, [:company_id, :id], algorithm: :concurrently, if_not_exists: true
  end
end
