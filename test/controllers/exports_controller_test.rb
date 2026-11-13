require "test_helper"

class ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = CompanyAdmin.create!(company: companies(:one), email: "a@example.test")
    other = companies(:two)
    emp = ->(c) { Employee.create!(company: c, email: "e#{c.id}@example.test") }
    mk = ->(c, status, at, json = { "answers" => [] }) {
      Assessment.create!(company: c, employee: emp.(c), employee_email: "secret@example.test", status: status, created_at: at, responses_json: json)
    }
    json = { "answers" => [{ "q" => "neck_pain", "type" => "scale", "value" => 4 }, { "q" => "notes", "type" => "text", "value" => "FREETEXT" },
                           { "q" => "back_pain", "type" => "scale", "value" => "n/a" }] }
    @mine = [mk.(companies(:one), "comp", "2025-03-01 10:00", json), mk.(companies(:one), "completed", "2025-03-05 23:59:59"),
             mk.(companies(:one), "done", "2025-03-06 00:00:01"), mk.(companies(:one), "pending", "2025-03-02")]
    @theirs = mk.(other, "completed", "2025-03-02")
    post session_path, params: { company_admin_id: @admin.id }
  end

  test "exports own company, inclusive end date, legacy statuses, no PII" do
    get export_path, params: { from: "2025-03-01", to: "2025-03-05", status: "completed", company_id: companies(:two).id }
    assert_response :success
    assert_match "attachment", response.headers["Content-Disposition"]
    lines = response.body.lines.map(&:chomp)
    assert_equal "assessment_id,created_on,status,neck_pain,back_pain,wrist_pain,eye_strain,chair_comfort", lines.first
    assert_equal ["#{@mine[0].id},2025-03-01,completed,4,,,,", "#{@mine[1].id},2025-03-05,completed,,,,,"], lines.drop(1)
    assert_no_match(/@|FREETEXT/, response.body)
  end

  test "logs one summary line with counts only" do
    out = StringIO.new
    ActionController::Base.logger = Logger.new(out)
    get export_path, params: { from: "2025-03-01", to: "2025-03-05", status: "completed" }
    assert_equal 1, out.string.scan("export company=").size
    assert_includes out.string, "rows=2 status=completed from=2025-03-01 to=2025-03-05"
    assert_no_match(/@|FREETEXT/, out.string)
  ensure
    ActionController::Base.logger = Rails.logger
  end

  test "invalid params give 422" do
    [{ from: "bad", to: "2025-01-01" }, { from: "2025-01-01" }, { from: "2025-02-01", to: "2025-01-01" },
     { from: "2025-01-01", to: "2025-02-01", status: "bogus" }].each do |p|
      get export_path, params: p
      assert_response :unprocessable_entity
    end
  end

  test "logged out gets no data" do
    delete session_path
    get export_path, params: { from: "2025-03-01", to: "2025-03-05" }
    assert_redirected_to new_session_path
  end
end
