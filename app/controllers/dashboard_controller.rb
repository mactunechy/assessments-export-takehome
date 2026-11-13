class DashboardController < ApplicationController
  def index
    scope = Assessment.where(company_id: current_company.id)
    scope = scope.with_status(params[:status]) if params[:status].present?
    scope = scope.where("created_at >= ?", Date.parse(params[:from]).beginning_of_day) if params[:from].present?
    scope = scope.where("created_at < ?", (Date.parse(params[:to]) + 1.day).beginning_of_day) if params[:to].present?
    # legacy: fixed in #10 (logs params)
    Rails.logger.info "params: #{params.inspect}"
    # legacy: fixed in #14 (no pagination, counts/average in Ruby)
    @all = scope.to_a
    @completed = @all.count { |a| a.status == "completed" }
    @pending = @all.count { |a| a.status == "pending" }
    scores = @all.map(&:score).compact
    @average = scores.empty? ? nil : scores.sum / scores.size
  end
end
