require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    co = companies(:one)
    admin = CompanyAdmin.create!(company: co, email: "a@example.test")
    mk = ->(c, status, at) {
      e = Employee.create!(company: c, email: "e#{rand(1e9)}@example.test", name: "Emp")
      Assessment.create!(company: c, employee: e, status: status, created_at: at, responses_json: { "answers" => [{ "value" => 4 }] })
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
end
