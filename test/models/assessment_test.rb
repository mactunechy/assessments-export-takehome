require "test_helper"

class AssessmentTest < ActiveSupport::TestCase
  test "with_status expands legacy aliases only" do
    sql = Assessment.with_status("completed").to_sql
    %w[completed complete comp done].each { |s| assert_includes sql, "'#{s}'" }
    assert_not_includes sql, "pending"
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
