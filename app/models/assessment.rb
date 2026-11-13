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

  # legacy: fixed in #15 (text and "n/a" count as 0, integer division, rescue nil hides bad data)
  def score
    answers = responses_json["answers"]
    answers.sum { |it| it["value"].to_i } / answers.size
  rescue
    nil
  end
end
