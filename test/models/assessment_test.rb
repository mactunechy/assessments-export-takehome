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
end
