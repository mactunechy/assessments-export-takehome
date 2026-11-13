class SessionsController < ApplicationController
  skip_before_action :require_admin

  def new
    @admins = CompanyAdmin.includes(:company).order(:id)
  end

  def create
    admin = CompanyAdmin.find(params[:company_admin_id])
    reset_session
    session[:company_admin_id] = admin.id
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end
end
