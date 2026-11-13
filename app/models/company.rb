class Company < ApplicationRecord
  has_many :company_admins
  has_many :employees
  has_many :assessments
end
