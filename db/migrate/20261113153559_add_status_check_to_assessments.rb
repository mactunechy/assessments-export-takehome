# RUN ONLY AFTER the status backfill and mop-up (assessments:backfill_status[false]); see SOLUTION.md release plan.
#
# Ordering: a NOT VALID constraint is still enforced for every new INSERT and UPDATE immediately,
# so updating a not-yet-backfilled row would fail. Backfill first, then add the constraint.
#
# Locking: on a large table add_check_constraint takes a brief ACCESS EXCLUSIVE lock (catalog change
# only, no table scan because of NOT VALID). Run it with a short lock_timeout and retry if it times
# out, e.g. PGOPTIONS='-c lock_timeout=2s' bin/rails db:migrate.
#
# Existing rows are checked by the next migration (ValidateStatusCheckOnAssessments).
class AddStatusCheckToAssessments < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :assessments,
      "status IS NOT NULL AND status IN ('pending','in_progress','completed','needs_follow_up','archived')",
      name: "assessments_status_allowed", validate: false
  end
end
