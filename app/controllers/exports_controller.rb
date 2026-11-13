require "csv"

class ExportsController < ApplicationController
  def index
    # legacy: fixed in #9 (cross-tenant: trusts params[:company_id]; builds whole CSV in memory; emails + raw JSON)
    rows = Assessment.where(company_id: params[:company_id])
    csv = CSV.generate do |out|
      out << %w[id employee_email status score responses_json created_at]
      rows.each { |a| out << [a.id, a.employee_email, a.status, a.score, a.responses_json.to_json, a.created_at] }
    end
    # legacy: fixed in #16 (logs response JSON)
    Rails.logger.info "export responses_json: #{rows.map(&:responses_json).to_json}"
    send_data csv, filename: "assessments.csv", type: "text/csv"
  end
end
