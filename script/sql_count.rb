# Loaded with RUBYOPT=-r. Appends one line per request to $MEASURE_OUT:
#   status total_ms views_ms activerecord_ms gc_ms allocations sql_queries (SCHEMA/CACHE skipped). No row data.
require "active_support"
require "active_support/notifications"
$sql_n = 0
ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| $sql_n += 1 unless %w[SCHEMA CACHE].include?(p[:name]) || p[:cached] }
ActiveSupport::Notifications.subscribe("start_processing.action_controller") { $sql_n = 0 }
ActiveSupport::Notifications.monotonic_subscribe("process_action.action_controller") do |e|
  p = e.payload
  File.open(ENV.fetch("MEASURE_OUT"), "a") { |f| f.puts [p[:status], e.duration.round, p[:view_runtime].to_f.round(1), p[:db_runtime].to_f.round(1), e.gc_time.round(1), e.allocations, $sql_n].join(" ") }
end
