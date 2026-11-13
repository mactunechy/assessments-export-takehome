module ApplicationHelper
  def score_label(assessment) = assessment.score || "Not scored"
end
