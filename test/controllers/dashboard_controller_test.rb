require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "filtered dashboard request logs no emails, names or answer text" do
    admin = CompanyAdmin.create!(company: companies(:one), email: "admin@example.test")
    emp = Employee.create!(company: companies(:one), email: "emp@example.test")
    Assessment.create!(company: companies(:one), employee: emp, employee_email: "secret@example.test", status: "completed",
                       created_at: "2025-03-01", responses_json: { "answers" => [{ "q" => "notes", "type" => "text", "value" => "FREETEXT" }] })
    post session_path, params: { company_admin_id: admin.id }

    out = StringIO.new
    old = Rails.logger
    Rails.logger = ActionController::Base.logger = Logger.new(out)
    get dashboard_path, params: { status: "completed", from: "2025-01-01", to: "2025-12-31" }
    assert_response :success
    assert_match "status", out.string # the request was logged
    assert_no_match(/example\.test|FREETEXT|"answers"/, out.string)
  ensure
    Rails.logger = ActionController::Base.logger = old
  end
end
