# RUN ONLY AFTER the status backfill and mop-up, and after AddStatusCheckToAssessments;
# see SOLUTION.md release plan. Fails if any row still has a non-canonical or NULL status.
#
# Ordering: the NOT VALID constraint from the previous migration already rejects bad new writes
# immediately; this step only proves the existing rows comply.
#
# Locking: VALIDATE CONSTRAINT scans the table but takes only SHARE UPDATE EXCLUSIVE, so normal
# reads and writes continue. No short lock_timeout is needed.
class ValidateStatusCheckOnAssessments < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :assessments, name: "assessments_status_allowed"
  end
end
