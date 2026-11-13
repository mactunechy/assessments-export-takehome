# Solution

Sections for the other tasks are added by later issues.

## Task 3: Status normalization: release and rollback

**Design only. Nothing here has been executed against a shared or production database.** Claims are tagged **[verified]** (checked against the current official docs listed at the end) or **[unverified]** (not confirmed; check before relying on it).

### What exists in the repo

| Piece | What it does |
|---|---|
| `Assessment` model | On every save: strip, downcase, alias `complete`/`comp`/`done` to `completed`, blank to `pending`; then `validates :status, inclusion: STATUSES`. `status` stays a plain string (no `enum`, no `normalizes`). |
| `legacy_status` column | Nullable string, no default. Keeps the original value of any row the backfill changes. |
| Bypass audit | Outside the model, only two things write `status` without validation: `db/seeds.rb` (raw SQL, on purpose, so a fresh clone has messy legacy data) and the backfill task. Reads already tolerate legacy values (`with_status` expands aliases, the CSV export canonicalizes). |
| `assessments:backfill_status[dry_run,batch,sleep]` | Dry run by default (`batch` 5000, `sleep` 0.2 s). Prints counts per status value only, never row data. Real run: id-range batches, one short transaction each, skips already-canonical rows (idempotent, resumable), does not touch `updated_at`. |
| `AddStatusCheckToAssessments` | `CHECK (status IS NOT NULL AND status IN (...))` named `assessments_status_allowed`, added `NOT VALID`. |
| `ValidateStatusCheckOnAssessments` | `VALIDATE CONSTRAINT` for the same constraint. |

**Mapping** (matched on `lower(btrim(status))`):

| Stored value | Becomes | `legacy_status` |
|---|---|---|
| `pending`, `in_progress`, `completed`, `needs_follow_up`, `archived` | unchanged | stays NULL (row skipped) unless it only differed by case or whitespace, then original kept |
| `complete`, `comp`, `done` | `completed` | original kept |
| `NULL`, `""`, `n/a` | `pending` | original kept (NULL stays NULL) |
| anything else | **nothing changes: the task prints the values and exits 1** | n/a |

**Write vs backfill policy (deliberate asymmetry):** on write, `n/a` is **rejected** (validation error) and only blank defaults to `pending`; on backfill, `n/a` is **mapped** to `pending`, because history cannot be re-asked. Unknown values are never guessed: a human extends the mapping and reruns.

**Schema decision (from #21):** `db/schema.rb` deliberately has the version bump but **no constraint line**, so a fresh clone seeds legacy statuses without the CHECK rejecting them. The constraint exists only where the two migrations are actually run, which is the release step below. Do not commit a schema dump that adds it.

### Principles

- **Expand, migrate data, contract.** Each step is backward compatible with the code running before it.
- **Long operations never run in the release phase.** It has a hard 1-hour limit that cannot be extended, and a failed release is not deployed **[verified]**. Heroku's own advice is to use `heroku run` for schema/data corrections **[verified]**. Use `heroku run:detached` so the work is not tied to your terminal **[verified]**.
- **Backfill before the constraint**, always (see "Ordering rule").
- **Short locks only.** Anything needing `ACCESS EXCLUSIVE` runs with a short `lock_timeout` and is retried, never waited on.
- **Back up first, but treat `legacy_status` as the real undo.** A restore loses later writes.

> **Repo caveat: migration timing.** The two constraint migrations are already on `main`. If the app runs `db:migrate` in the Heroku release phase (there is no Procfile in this repo, so this is an assumption about the target), deploying `main` would run them before the backfill: the first would enforce the CHECK on new writes, the second would fail on legacy rows and fail the release. So Deploy A must be built from a commit that contains only the `legacy_status` migration; the constraint migrations ship in a later release (steps 8-9) or are run by hand.

### Release plan

| # | Step | Safe live? | Low-traffic window? | Rollback |
|---|---|---|---|---|
| 1 | **Rehearse** the whole sequence on a production-size copy (a fork attached to a scratch app, not the live app). Record how long the dry run, a batch, and `VALIDATE` take. | Yes: separate database. | No. | Destroy the scratch fork/app. |
| 2 | **Capture and verify a backup.** | Yes, but adds load. | Prefer off-peak. | n/a (see recovery ladder). |
| 3 | **Record the current state:** release number and rollback support. | Yes. | No. | n/a |
| 4 | **Pre-flight dry run** (read-only). Gate: **unknown must be 0**. | Yes: read-only, but a full scan (IO). | Prefer off-peak. | n/a |
| 5 | **Deploy A:** canonicalizing model + `legacy_status` column (only this migration). | Yes: additive; old and new code coexist. `ADD COLUMN` with no default is metadata only, no rewrite **[verified]**, but still takes `ACCESS EXCLUSIVE` briefly **[verified]**, so use `lock_timeout`. | No. | `heroku releases:rollback vN` (code). Leave the column. |
| 6 | **Backfill**, throttled, via `run:detached`. | Yes if throttled; each batch is a short transaction. | Run the bulk in a window: it rewrites most non-canonical rows (dead tuples, WAL, replica lag). | Reverse from `legacy_status` in batches (recovery ladder step 3). |
| 7 | **Mop-up and re-check:** rerun the backfill, then the dry run. Gate: unknown 0 and every row canonical. | Yes. | No. | n/a (idempotent). |
| 8 | **Add CHECK ... NOT VALID** (`AddStatusCheckToAssessments`). | Conditionally: only the lock is risky. Brief `ACCESS EXCLUSIVE`, no scan **[verified]**; if a long transaction holds the table, this request queues and everything behind it queues too. | **Yes**, and run it with a short `lock_timeout`, retrying on timeout. | `ALTER TABLE assessments DROP CONSTRAINT assessments_status_allowed` (also brief `ACCESS EXCLUSIVE`). |
| 9 | **VALIDATE CONSTRAINT** (`ValidateStatusCheckOnAssessments`). | Yes: `SHARE UPDATE EXCLUSIVE`, does not block ordinary reads or writes **[verified]**. | Recommended for IO (full scan). It conflicts with `VACUUM`/`ANALYZE` and other DDL on the table while it runs **[verified]**, so do not start it during a manual vacuum. | If it fails: it names offenders; backfill them and retry. The constraint stays `NOT VALID` meanwhile, still enforced on new writes. Or drop it (step 8 rollback). |
| 10 | **Verify:** counts per status, dashboard and export smoke test, error rate, `pg:diagnose`. | Yes. | No. | n/a |
| 11 | **Contract, later release after a bake period:** drop `legacy_status`. | Brief `ACCESS EXCLUSIVE` per DDL. | Yes, with `lock_timeout`. | Re-add the column, but **the original values are gone**: so only after backups and the bake period. |

The `(company_id, id)` index already shipped in #8 as a concurrent migration, so there is no index step here.

### Commands, by step

**1. Rehearse.** Fork the production database onto a *scratch* app: `heroku addons:create heroku-postgresql:standard-0 --app SCRATCH_APP -- --fork PROD_APP::HEROKU_POSTGRESQL_COLOR_URL` **[verified]**. Forking is Standard tier or higher (not Essential), can take minutes to hours, and forking onto the live app would set a config var that restarts it **[verified]**. Check progress with `heroku pg:wait --app SCRATCH_APP` **[verified]**. `heroku pg:copy SOURCE TARGET` also exists **[verified]**. Deploy the same commits to the scratch app and run steps 4-10 there.

**2. Backup.**
```
heroku pg:backups:capture --app APP        # [verified]
heroku pg:backups --app APP                # list, shows status [verified]
heroku pg:backups:info BACKUP_ID --app APP # expect Status: Completed and a non-zero size [verified]
```
- There is no documented dedicated "verify" command **[verified]**. `Completed` plus a plausible size is the minimum. The real proof is restoring into a scratch app: `heroku pg:backups:restore APP::BACKUP_ID DATABASE_URL --app SCRATCH_APP` **[verified]**, then compare row counts.
- **Size limit:** PGBackups is for moderately loaded databases **up to 20 GB**; heavily loaded, larger, or many-schema/large-object databases can time out **[verified]**. For those, Heroku documents a logical backup: `pg_dump` against a short-lived fork (not the primary), run on a detached Performance-L/Private-L/Shield-L one-off dyno **[verified]**. One-off dynos are cycled about every 24 hours, so a very large dump may need to run outside Heroku **[verified]**.
- **Plan support:** PGBackups is not supported on Heroku Postgres Advanced; Essential has PGBackups (5 manual, 7 daily) but no rollback, forks or followers; continuous protection with rollback needs Standard tier or higher **[verified]**. Advanced uses `heroku data:pg:fork ... --rollback-to` **[verified]**.
- If the leader is busy, Heroku suggests taking backups from a follower **[verified]** (no command syntax given).

**3. Record state.**
```
heroku releases --app APP                  # note the current vN [verified]
heroku pg:info --app APP                   # "Rollback:" line: earliest point, "Unsupported", or "Capturing Snapshot" [verified]
```

**4 and 7. Dry run** (default; prints counts only):
```
heroku run:detached --app APP 'bin/rails assessments:backfill_status'
heroku logs --dyno run.N --app APP         # N printed by the previous command [verified]
```
Read the output: every line must map to a target and there must be no `ABORT`. If it aborts, a human decides what each listed unknown value means, extends `Assessment::LEGACY_ALIASES`, redeploys, and reruns. (The `run:detached` syntax is verified; quoting the bracketed rake argument through the dyno shell is **[unverified]**, settle it in the rehearsal.)

**6. Backfill:**
```
heroku run:detached --app APP "bin/rails 'assessments:backfill_status[false,5000,0.2]'"
```
- Resumable: if the dyno is cycled or you stop it (`heroku ps:stop run.N` **[verified]**), rerun the same command and it continues.
- Watch while it runs: `heroku pg:locks`, `heroku pg:blocking`, `heroku pg:info`, `heroku pg:vacuum-stats` (dead rows, autovacuum) **[verified: commands exist; `pg:vacuum-stats` has only a one-line description in the docs]**; and follower lag. Raise `sleep` or lower `batch` if lag or lock waits grow. `heroku pg:kill PID` cancels a stuck query **[verified]**.
- The task prints only status values and counts, so its output in the Heroku logs contains no row data.

**8. NOT VALID.** The migration header documents the invocation: `PGOPTIONS='-c lock_timeout=2s' bin/rails db:migrate`. How to pass that env var through `heroku run` is **[unverified]** (the CLI has an `-e/--env` flag on `run:detached` **[verified]**); rehearse it, and confirm the timeout is applied before the real run. Retry on `lock timeout` errors; check `heroku pg:blocking` for the long transaction.

**9. VALIDATE.** Same `db:migrate`; no short `lock_timeout` is needed because the lock does not block normal traffic. Run it detached if it may exceed your terminal session.

### Ordering rule: backfill first, then NOT VALID

`ADD CONSTRAINT ... NOT VALID` skips the scan of existing rows, but the constraint is **enforced against subsequent inserts and updates immediately** **[verified]**. So once step 8 runs, any `UPDATE` of a row that still has a legacy status (even `touch`, or a change to an unrelated column) fails the CHECK on the new row version. The order is therefore: Deploy A, backfill, mop-up, **then** `NOT VALID`, **then** `VALIDATE`. `NOT VALID` is not "safe because it's lazy": it is only cheap, not harmless.

The CHECK includes `status IS NOT NULL` because a bare `CHECK (status IN (...))` passes NULL (the result is NULL, not false), so no separate `SET NOT NULL` is needed.

### Recovery ladder (try in order)

| # | Situation | Action | Cost / caveat |
|---|---|---|---|
| 1 | Bad code | `heroku releases:rollback vN --app APP` **[verified]** (the Heroku releases article names it `heroku rollback`; the CLI reference lists `releases:rollback` **[verified]**) | Creates a new release with the old slug and config vars; does **not** roll back the database or add-on state; only the 20 most recent releases within 30 days are available **[verified]**. Safe here because every schema change so far is additive. |
| 2 | Constraint rejects legitimate writes (a writer path was missed) | `ALTER TABLE assessments DROP CONSTRAINT assessments_status_allowed;` (short `lock_timeout`, retry), fix the writer, retry from step 8 | Brief `ACCESS EXCLUSIVE`. No data lost. |
| 3 | Bad backfill (wrong mapping chosen) | If the constraint exists, drop it first (row 2). Then reverse in id-range batches, same shape as the backfill: `UPDATE assessments SET status = legacy_status WHERE legacy_status IS NOT NULL AND id BETWEEN :lo AND :hi` | Exact undo for every row the backfill changed, except rows whose original was NULL: `legacy_status` is NULL there, so they stay `pending`. Rows a user edited after the backfill are overwritten with the old value; restrict by `updated_at` if that matters. Keep `legacy_status` until this rung is no longer needed (step 11). |
| 4 | Catastrophic data problem (last resort) | **Preferred: a new database.** Continuous-protection rollback: `heroku addons:create heroku-postgresql:standard-0 --as ROLLBACK_X --app APP -- --rollback DATABASE --to '2026-01-01 12:00+00:00'`, then `heroku pg:wait`, inspect it, then `heroku pg:promote ADDON --app APP` **[verified]**. Recreate followers afterwards **[verified]**. **Otherwise:** `heroku pg:backups:restore BACKUP_ID DATABASE_URL --app APP`. | Both lose every write after the recovery point. Rollback is not accurate to the second and retention depends on the plan **[verified]**. `pg:backups:restore` **deletes all data in the target first** **[verified]**. Put the app in maintenance mode and stop dynos writing before a restore. Steps 1-3 exist so this is rarely needed. |

### Sources checked (current official docs)

Heroku Dev Center: Release Phase; Heroku Postgres Backups; Logical Backups of a large database; Continuous Protection; Rollback; Fork; Releases; One-Off Dynos / Working with One-Off Dynos; Managing Heroku Postgres Using the CLI; Heroku CLI command reference (command names and usage lines for `pg:backups:*`, `pg:info`, `pg:locks`, `pg:blocking`, `pg:diagnose`, `pg:promote`, `pg:wait`, `pg:copy`, `releases`, `releases:rollback`, `run:detached`). PostgreSQL: `ALTER TABLE` and "Explicit Locking" (current).

**Unverified, check in the rehearsal:** quoting the bracketed rake argument through `heroku run:detached`; passing `PGOPTIONS` through `heroku run`; exact output of `pg:backups:info` (the docs say only that it shows status and size); retention length for the rollback window on your plan (read it from `pg:info`); `pg:vacuum-stats`, `pg:bloat` and `pg:outliers` usage lines (the CLI reference was only read for the commands named above).
