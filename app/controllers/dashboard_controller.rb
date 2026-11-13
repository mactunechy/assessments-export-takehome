class DashboardController < ApplicationController
  PER_PAGE = 50

  def index
    scope = current_company.assessments
    scope = scope.with_status(params[:status]) if params[:status].present?
    scope = scope.created_between(params[:from].present? ? Date.parse(params[:from]) : Date.new(1970),
                                  params[:to].present? ? Date.parse(params[:to]) : Date.current) if params[:from].present? || params[:to].present?
    @counts = scope.group(:status).count.each_with_object(Hash.new(0)) { |(s, n), h| h[Assessment::LEGACY_ALIASES.fetch(s, s)] += n }
    @total = @counts.values.sum
    @page = [params[:page].to_i, 1].max
    @assessments = scope.includes(:employee).select(:id, :employee_id, :status, :created_at, :responses_json)
                        .order(created_at: :desc, id: :desc).limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
    @has_next = @page * PER_PAGE < @total
  end
end
