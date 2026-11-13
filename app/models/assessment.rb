class Assessment < ApplicationRecord
  belongs_to :company
  belongs_to :employee

  STATUSES = %w[pending in_progress completed needs_follow_up archived].freeze
  LEGACY_ALIASES = { "complete" => "completed", "comp" => "completed", "done" => "completed" }.freeze

  scope :with_status, ->(canonical) {
    where(status: [canonical, *LEGACY_ALIASES.select { |_, v| v == canonical }.keys])
  }
  # half-open range over whole days, UTC
  scope :created_between, ->(from, to) {
    where(created_at: from.to_date.beginning_of_day...(to.to_date + 1.day).beginning_of_day)
  }

  # 0-100 from the mean of valid scale answers (integers 1-5); nil when there is nothing to score.
  # ponytail: computed per visible row / streamed row; persist a score column when sorting, filtering or averaging by score across all rows.
  def score
    answers = responses_json.is_a?(Hash) ? responses_json["answers"] : nil
    values = Array(answers).grep(Hash).select { |a| a["type"] == "scale" && a["value"].is_a?(Integer) && a["value"].between?(1, 5) }.map { |a| a["value"] }
    ((values.sum.fdiv(values.size) - 1) / 4.0 * 100).round if values.any?
  end
end
