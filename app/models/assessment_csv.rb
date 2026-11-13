require "csv"

# Yields CSV lines for one company's assessments. Allowlist only; fails closed on anything unexpected.
class AssessmentCsv
  EXPORTABLE_QUESTIONS = %w[neck_pain back_pain wrist_pain eye_strain chair_comfort].freeze
  HEADER = (%w[assessment_id created_on status] + EXPORTABLE_QUESTIONS + %w[score]).freeze

  # score is empty (not 0) when there is nothing to score.
  def initialize(scope) = @scope = scope

  def each_line
    yield CSV.generate_line(HEADER)
    @scope.select(:id, :created_at, :status, :responses_json).find_each do |a|
      yield CSV.generate_line([a.id, a.created_at.to_date.iso8601, canonical(a.status), *scales(a.responses_json), a.score])
    end
  end

  private

  def canonical(status) = Assessment::LEGACY_ALIASES.fetch(status, status).presence_in(Assessment::STATUSES)

  # Integer scale values only; text, "n/a", null and missing answers become blank.
  def scales(json)
    answers = json.is_a?(Hash) && json["answers"].is_a?(Array) ? json["answers"] : []
    by_q = answers.grep(Hash).select { |x| x["type"] == "scale" && x["value"].is_a?(Integer) }.to_h { |x| [x["q"], x["value"]] }
    EXPORTABLE_QUESTIONS.map { |q| by_q[q] }
  end
end
