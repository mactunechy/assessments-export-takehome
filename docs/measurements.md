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
| Code measured | Before: git tag `legacy-baseline` (extracted with `git archive`, then `npm install && npm run build`). After: `main` at 80f4c8f (dashboard fix #14, score fix #15), built in place |

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

## After (main at 80f4c8f), median of 5 warm runs

Same commands, machine, seeded database (not reseeded) and method as Before: 6 requests, run 1 cold and discarded, warm runs 2-6. Machine idle. The script needed no changes.

| Metric | Median | Warm range | Cold run (discarded) |
|---|---|---|---|
| SQL queries (non-SCHEMA, non-CACHE) | **5** | 5 | 5 |
| Total (Rails `Completed 200 OK in`) | **59 ms** | 54 - 79 ms | 806 ms |
| Views | 4.2 ms | 4.1 - 4.8 ms | 10.9 ms |
| ActiveRecord | **51.0 ms** | 47.2 - 71.6 ms | 782.8 ms |
| GC | 0.0 ms | 0.0 ms | 1.1 ms |
| Allocations | **7,470** | 7,470 - 7,476 | 17,292 |
| curl `time_total` | 0.062 s | 0.057 - 0.083 s | 0.81 s |

The 5 queries: current admin, company, status counts (`GROUP BY status`), the page (`LIMIT 50`), and the preloaded employees (one `IN` query for the page).

## Before / after

| Metric | Before (median) | After (median) | Change |
|---|---|---|---|
| SQL queries | 2006 | 5 | -99.8% |
| Total | 59,382 ms | 59 ms | ~1000x faster |
| ActiveRecord | 2,144 ms | 51.0 ms | -98% |
| Allocations | 54,715,435 | 7,470 | ~7,300x fewer |
| curl `time_total` | 59.5 s | 0.062 s | ~960x faster |

## After: EXPLAIN (ANALYZE, BUFFERS)

Status-count query (`SELECT COUNT(*), status ... WHERE company_id = 1 GROUP BY status`):

```
HashAggregate  (cost=9760.76..9760.86 rows=10 width=16) (actual time=62.244..62.247 rows=11 loops=1)
  Group Key: status
  Batches: 1  Memory Usage: 24kB
  Buffers: shared hit=7192
  ->  Index Scan using index_assessments_on_company_id on assessments  (cost=0.30..9257.83 rows=100585 width=8) (actual time=0.052..45.647 rows=100000 loops=1)
        Index Cond: (company_id = 1)
        Buffers: shared hit=7192
Planning Time: 0.843 ms
Execution Time: 62.420 ms
```

Page query (`... WHERE company_id = 1 ORDER BY created_at DESC, id DESC LIMIT 50 OFFSET 0`):

```
Limit  (cost=11809.19..11814.94 rows=50 width=479) (actual time=25.255..27.127 rows=50 loops=1)
  Buffers: shared hit=7276
  ->  Gather Merge  (cost=11809.19..18613.51 rows=59168 width=479) (actual time=25.254..27.123 rows=50 loops=1)
        Workers Planned: 1
        Workers Launched: 1
        ->  Sort  (cost=10809.18..10957.10 rows=59168 width=479) (actual time=23.518..23.520 rows=26 loops=2)
              Sort Key: created_at DESC, id DESC
              Sort Method: top-N heapsort  Memory: 78kB
              ->  Parallel Index Scan using index_assessments_on_company_id on assessments  (cost=0.30..8843.66 rows=59168 width=479) (actual time=0.015..12.129 rows=50000 loops=2)
                    Index Cond: (company_id = 1)
                    Buffers: shared hit=7262
Planning Time: 0.459 ms
Execution Time: 27.173 ms
```

(The two plans are from `psql`, one run each, so their times differ a little from the in-request times of 26.7 ms and 20.1 ms.)

## Index decision

No dashboard index was added, and the evidence supports that. Both queries use the existing `index_assessments_on_company_id` and read about 7,200 buffers, all cache hits. Together they cost about 47-50 ms of the 59 ms request, so SQL is now roughly the whole request, but 59 ms is already ~1000x lower than before and well inside what a dashboard needs.

A `(company_id, created_at DESC, id DESC)` index would let the page query skip the top-N sort, but the status-count query still has to visit all 100,000 BigCo rows, so the request would only drop by the ~25 ms page-query cost. That is not worth a migration and extra write cost on the largest table. Revisit if a company grows well beyond 100k assessments or if the count is cached or denormalised. Not measured with an index: this issue adds no migrations.

## Why this change

The baseline showed SQL took about 57 ms of about 59 s. The time was in instantiating 100,000 records, rendering them in the view (47.8-70.8 s of Views, 54.7M allocations) and GC, plus a per-row employee N+1. Bounding the page to 50 rows and preloading employees attacks those dominant costs directly: work now scales with the page size, not the company size. The only cost left that scales with company size is the single status-count aggregate (about 25-60 ms for 100k rows).

## Re-run exactly

From any checkout (`CHECKOUT` is the code under test; port must be free; needs the same seeded DB, do not reseed):

```sh
cd "$CHECKOUT" && bundle install && npm install && npm run build    # build output is gitignored
script/measure_dashboard.sh "$CHECKOUT" 3999 6                      # script lives in this repo: pass its path if CHECKOUT differs
```

Baseline: `mkdir /tmp/baseline && git archive legacy-baseline | tar -x -C /tmp/baseline`, then the two commands above with `CHECKOUT=/tmp/baseline` (using the `script/` files from this branch). The baseline takes about 7 minutes (one request is about a minute); the After run takes seconds.

The script boots `bin/rails server` in development, logs in as BigCo's first admin, requests `/dashboard` 6 times, aborts on any non-200, and prints per-request numbers plus the warm medians. `script/sql_count.rb` (loaded via `RUBYOPT`) subscribes to `sql.active_record` (skipping SCHEMA/CACHE) and `process_action.action_controller`. Only counts and timings are recorded, no row data.

EXPLAIN (Before; for After, run the two statements shown in the After section the same way):

```sh
psql assessments_export_takehome_development -c 'EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 1'
```

Row counts: `psql assessments_export_takehome_development -Atc "select count(*) from assessments"` (and `where company_id=1`, `employees`, `companies`, `company_admins`).
