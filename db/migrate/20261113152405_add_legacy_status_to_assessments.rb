class AddLegacyStatusToAssessments < ActiveRecord::Migration[8.1]
  def change
    add_column :assessments, :legacy_status, :string
  end
end
