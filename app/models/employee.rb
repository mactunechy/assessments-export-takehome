class Employee < ApplicationRecord
  has_many :assessments
  belongs_to :company
end
