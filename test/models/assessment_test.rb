require "test_helper"

class AssessmentTest < ActiveSupport::TestCase
  test "with_status expands legacy aliases only" do
    sql = Assessment.with_status("completed").to_sql
    %w[completed complete comp done].each { |s| assert_includes sql, "'#{s}'" }
    assert_not_includes sql, "pending"
  end

  def build(status) = Assessment.new(company: companies(:one), employee: employees(:one), status: status)

  test "create canonicalizes case, whitespace and aliases" do
    assert_equal "completed", build(" DONE ").tap(&:save!).status
    assert_equal "in_progress", build("In_Progress").tap(&:save!).status
  end

  test "create with nil or blank status stores pending" do
    [nil, "", "  "].each { |s| assert_equal "pending", build(s).tap(&:save!).reload.status }
    assert_equal "pending", Assessment.new(company: companies(:one), employee: employees(:one)).tap(&:save!).status
  end

  test "unknown statuses fail validation" do
    %w[foo n/a].each do |s|
      a = build(s)
      assert_not a.valid?
      assert a.errors.of_kind?(:status, :inclusion)
    end
    assert_raises(ActiveRecord::RecordInvalid) { build("foo").save! }
  end

  test "any save of a legacy row self-heals the status" do
    a = build("pending").tap(&:save!)
    a.update_column(:status, "comp")
    assert_equal "comp", Assessment.find(a.id).status # reads keep working
    a = Assessment.find(a.id)
    a.update!(employee_email: "x@example.test")
    assert_equal "completed", a.reload.status
  end

  test "update to an unknown status fails" do
    a = build("pending").tap(&:save!)
    assert_not a.update(status: "n/a")
  end

  test "created_between is inclusive of the end day and excludes the next" do
    d = Date.new(2024, 3, 5)
    sql = Assessment.created_between(d, d).to_sql
    assert_includes sql, "2024-03-05 00:00:00"
    assert_includes sql, "2024-03-06 00:00:00"
    assert_includes sql, "< '2024-03-06"
  end

  def score_of(*answers, json: { "answers" => answers }) = Assessment.new(responses_json: json).score
  def scale(v) = { "q" => "neck_pain", "type" => "scale", "value" => v }

  test "score all fives is 100 and all ones is 0" do
    assert_equal 100, score_of(scale(5), scale(5))
    assert_equal 0, score_of(scale(1), scale(1))
  end

  test "score is the mean mapped to 0-100" do
    assert_equal 50, score_of(scale(3))
    assert_equal 58, score_of(scale(2), scale(3), scale(5)) # mean 3.33
  end

  test "score ignores text, n/a and nil values" do
    noise = [{ "q" => "notes", "type" => "text", "value" => "hi" }, scale("n/a"), scale(nil), { "q" => "c", "type" => "choice", "value" => 1 }]
    assert_equal 100, score_of(scale(5), *noise)
  end

  test "score is nil with nothing to score" do
    assert_nil score_of
    assert_nil score_of(scale("n/a"))
    assert_nil score_of(json: {})
    assert_nil score_of(json: nil)
    assert_nil score_of(json: { "answers" => "bad" })
  end
end
