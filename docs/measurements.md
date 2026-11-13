# Dashboard measurements

Target: `GET /dashboard` as BigCo's first admin (company 1, 100,000 assessments).

## Environment

| | |
|---|---|
| Hardware | Apple M3 Pro, 18 GB RAM, macOS 26.6.2 |
| Ruby / Rails / PostgreSQL | 3.4.7 / 8.1.4.1 / 17.9 (Homebrew, local) |
| Mode | Rails **development** (puma, code reloading on, default dev logging) |
| Data | `assessments_export_takehome_development`, `db:seed` default scale: 282,754 assessments (BigCo 100,000), 5,611 employees, 107 companies, 214 admins |
| Index | `index_assessments_on_company_id_and_id` (from #8) is present in this database; the `legacy-baseline` code does not use it |
| Code measured | git tag `legacy-baseline` (extracted with `git archive`, then `npm install && npm run build`) |

## Before (legacy-baseline), median of 5 warm runs

Run 1 of 6 is a cold run and is discarded. Warm runs: 2-6.

| Metric | Median | Warm range |
|---|---|---|
| SQL queries (non-SCHEMA, non-CACHE) | **2006** | 2006 |
| Total (Rails `Completed 200 OK in`) | **59,382 ms** | 51,363 - 74,981 |
| Views | 55,966 ms | 47,848 - 70,771 |
| ActiveRecord | **2,144 ms** | 1,774 - 2,760 |
| GC | 12,282 ms | 9,549 - 17,385 |
| Allocations | **54,715,435** | 54.7M - 54.8M |
| curl `time_total` | 59.5 s | 51.5 - 68.0 |

Notes:
- Rails 8.1's log line prints `GC:` rather than `Allocations:`; the script reads allocations from the same `process_action.action_controller` event instead.
- Rails also reports `100003 queries, 97997 cached` for the request (the per-employee N+1 is mostly served from the query cache); 2006 is the uncached count.
- Timing varies roughly +/-20% run to run; the query count and allocations are stable.

Main query (`Assessment.where(company_id: 1)`, no LIMIT), `EXPLAIN (ANALYZE, BUFFERS)`:

```
Index Scan using index_assessments_on_company_id on assessments  (cost=0.30..9257.83 rows=100585 width=524) (actual time=0.033..54.148 rows=100000 loops=1)
  Index Cond: (company_id = 1)
  Buffers: shared hit=7192
Planning Time: 2.267 ms
Execution Time: 57.488 ms
```

The SQL itself is cheap (57 ms); the time goes to instantiating 100k records, the per-row view work and GC.

## Re-run exactly

From any checkout (`CHECKOUT` is the code under test; port must be free; needs the same seeded DB, do not reseed):

```sh
cd "$CHECKOUT" && bundle install && npm install && npm run build    # build output is gitignored
script/measure_dashboard.sh "$CHECKOUT" 3999 6                      # script lives in this repo: pass its path if CHECKOUT differs
```

Baseline: `mkdir /tmp/baseline && git archive legacy-baseline | tar -x -C /tmp/baseline`, then the two commands above with `CHECKOUT=/tmp/baseline` (using the `script/` files from this branch). Takes about 7 minutes (one request is about a minute).

The script boots `bin/rails server` in development, logs in as BigCo's first admin, requests `/dashboard` 6 times, aborts on any non-200, and prints per-request numbers plus the warm medians. `script/sql_count.rb` (loaded via `RUBYOPT`) subscribes to `sql.active_record` (skipping SCHEMA/CACHE) and `process_action.action_controller`. Only counts and timings are recorded, no row data.

EXPLAIN:

```sh
psql assessments_export_takehome_development -c 'EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 1'
```

Row counts: `psql assessments_export_takehome_development -Atc "select count(*) from assessments"` (and `where company_id=1`, `employees`, `companies`, `company_admins`).
