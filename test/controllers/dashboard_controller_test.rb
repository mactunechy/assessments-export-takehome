require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    co = companies(:one)
    admin = CompanyAdmin.create!(company: co, email: "a@example.test")
    mk = ->(c, status, at) {
      e = Employee.create!(company: c, email: "e#{rand(1e9)}@example.test", name: "Emp")
      Assessment.create!(company: c, employee: e, status: status, created_at: at, responses_json: { "answers" => [{ "value" => 4 }] }).tap { |a| a.update_column(:status, status) } # raw write keeps legacy values
    }
    %w[completed comp done pending].each_with_index { |s, i| mk.(co, s, "2025-03-0#{i + 1} 10:00") }
    mk.(companies(:two), "completed", "2025-03-02")
    55.times { mk.(co, "pending", "2025-02-01") }
    post session_path, params: { company_admin_id: admin.id }
  end

  def queries
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless p[:name] == "SCHEMA" }
    yield
    n
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  test "pages of 50 with constant query count and legacy-aware summary" do
    q1 = queries { get dashboard_path }
    assert_select "table tr", 51 # header + 50
    assert_match "Total 60 · Completed 3 · Pending 56", response.body
    assert_select "a", text: "Next"
    assert_select "a", text: "Prev", count: 0
    q2 = queries { get dashboard_path, params: { page: 2 } }
    assert_select "table tr", 11
    assert_select "a", text: "Prev"
    assert_select "a", text: "Next", count: 0
    assert_equal q1, q2
    assert_operator q1, :<=, 6
  end

  test "filters match export scopes" do
    get dashboard_path, params: { status: "completed", from: "2025-03-01", to: "2025-03-03" }
    assert_match "Total 3 · Completed 3", response.body
  end

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
