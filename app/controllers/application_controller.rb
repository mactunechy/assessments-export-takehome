class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # ponytail: DEMO-ONLY stand-in for auth (pick-an-admin login, no passwords); replace with real auth.
  before_action :require_admin

  private

  def current_admin = (@current_admin ||= CompanyAdmin.find_by(id: session[:company_admin_id]))
  def current_company = current_admin&.company
  helper_method :current_admin, :current_company

  def require_admin
    redirect_to new_session_path unless current_admin
  end
end
