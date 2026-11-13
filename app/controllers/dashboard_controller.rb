class DashboardController < ApplicationController
  def index
    scope = Assessment.where(company_id: current_company.id)
    # legacy: fixed in #7 (exact status match; "to" date means midnight so the end day is excluded)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("created_at >= ?", params[:from]) if params[:from].present?
    scope = scope.where("created_at <= ?", params[:to]) if params[:to].present?
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
