class Assessment < ApplicationRecord
  belongs_to :company
  belongs_to :employee

  # legacy: fixed in #15 (text and "n/a" count as 0, integer division, rescue nil hides bad data)
  def score
    answers = responses_json["answers"]
    answers.sum { |it| it["value"].to_i } / answers.size
  rescue
    nil
  end
end
