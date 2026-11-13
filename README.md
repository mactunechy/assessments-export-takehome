# assessments-export-takehome

A small Rails imitation of a legacy assessments app: a company-scoped CSV export, a fixed dashboard, and a status normalization plan. Design rationale and trade-offs are in [SOLUTION.md](SOLUTION.md).

The `legacy-baseline` git tag holds the original code with its intentional defects; `git diff legacy-baseline` shows the fixes.

## Prerequisites

- Ruby 3.4.7 (see `.ruby-version`)
- PostgreSQL 14 or newer, running locally and reachable by your OS user (database names are in `config/database.yml`)
- Node 20 or newer (only for the `tsc` build)

## Setup

```sh
git clone https://github.com/mactunechy/assessments-export-takehome
cd assessments-export-takehome
bin/setup
```

`bin/setup` runs `bundle install`, `npm install && npm run build`, creates and migrates the database, seeds it, then starts the server on port 3000. The default seed (about 285,000 fake assessments) takes about 1.5 minutes in total. For a faster, smaller dataset set `SEED_SCALE`, for example `SEED_SCALE=0.1 bin/setup`.

- To set up without starting the server: `bin/setup --skip-server`.
- If you already have a dev database from an earlier checkout with pending migrations, setup can fail validating the status constraint on legacy rows. Run `bin/rails db:reset` (drops, recreates, migrates, reseeds), then `bin/setup`.
- Seeds are safe to rerun: `bin/rails db:seed` wipes and reloads.

## Run

```sh
bin/rails server            # http://localhost:3000
bin/rails server -p 3001    # if port 3000 is busy
```

Open `/session/new` and pick an admin (demo login, no password):

| Button | Company |
|---|---|
| Log in as BigCo admin #1 | BigCo (company 1, 100,000 assessments) |
| Log in as OtherCo admin #2 | OtherCo (company 2, 80,000 assessments) |

(The seed creates two admins per company; the other BigCo/OtherCo admins are further down the list.)

## Try it

After logging in, the dashboard is at `/dashboard`. The export takes `from` and `to` (ISO dates, required) and an optional `status`:

```
http://localhost:3000/export?from=2020-01-01&to=2030-01-01&status=completed
```

This downloads `assessments.csv` for your own company only. Accepted statuses: `pending`, `in_progress`, `completed`, `needs_follow_up`, `archived`.

**Check tenancy.** Log in as BigCo admin #1, then add `&company_id=2` to the export URL (or `/dashboard?company_id=2`). The response is identical to the one without it, and still contains only BigCo's rows: the company always comes from the session, never from params. Log in as OtherCo admin #2 and the same URL returns OtherCo's rows instead.

## Tests

```sh
bin/rails test
```

## Verify the logs stay clean

After using the app, no emails, employee names or answer text should be in the development log. This should print `0`:

```sh
grep -cE '@example\.test|"answers"|neck_pain|Employee [0-9]' log/development.log
```

Each export writes one summary line (company, row count, filters, no row data): `grep 'export company=' log/development.log`.

## Measure the dashboard against `legacy-baseline`

`script/measure_dashboard.sh CHECKOUT_DIR [PORT] [RUNS]` boots the given checkout, logs in as BigCo's first admin, requests `/dashboard` `RUNS` times (default 6, first run discarded as cold) and prints query count, time and allocations. It reads the default development database, so seed it first (see Setup).

```sh
# current code
script/measure_dashboard.sh .

# legacy baseline
mkdir /tmp/baseline && git archive legacy-baseline | tar -x -C /tmp/baseline
(cd /tmp/baseline && npm install && npm run build)
script/measure_dashboard.sh /tmp/baseline
```

The baseline takes several minutes (one request is about a minute); the current code takes seconds. Recorded results and environment are in [docs/measurements.md](docs/measurements.md).

## Caveats

- Demo auth only: the login page lists every admin and needs no password.
- All data is fake (`example.test` emails, generated answers). Do not load real data.
- The TypeScript is not built by Rails: after changing `.ts` files run `npm run build`.
- The seed deliberately writes messy legacy statuses (`complete`, `comp`, `done`, NULL, empty, `n/a`) with raw SQL; this is the data the status normalization plan handles.
