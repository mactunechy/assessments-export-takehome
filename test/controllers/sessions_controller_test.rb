require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "logged out redirects to login, login shows dashboard, logout clears" do
    get root_path
    assert_redirected_to new_session_path
    admin = CompanyAdmin.first
    post session_path, params: { company_admin_id: admin.id, company_id: 0 }
    follow_redirect!
    assert_select "h1", "#{admin.company.name} dashboard"
    delete session_path
    get root_path
    assert_redirected_to new_session_path
  end
end
