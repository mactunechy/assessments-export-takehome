class ExportsController < ApplicationController
  include ActionController::Live

  def show
    from, to = parse_date(params[:from]), parse_date(params[:to])
    status = params[:status].presence
    return invalid("from") unless from
    return invalid("to") unless to && from <= to
    return invalid("status") if status && !Assessment::STATUSES.include?(status)

    scope = current_company.assessments.created_between(from, to)
    scope = scope.with_status(status) if status
    send_stream(filename: "assessments.csv", type: "text/csv", disposition: "attachment") do |stream|
      lines = 0
      AssessmentCsv.new(scope).each_line { |line| stream.write(line); lines += 1 }
      logger.info "export company=#{current_company.id} rows=#{lines - 1} status=#{status || 'all'} from=#{from} to=#{to}"
    end
  end

  private

  def parse_date(value)
    Date.iso8601(value) if value.is_a?(String)
  rescue Date::Error
    nil
  end

  def invalid(field) = render(plain: "Invalid or missing #{field}", status: :unprocessable_entity)
end
