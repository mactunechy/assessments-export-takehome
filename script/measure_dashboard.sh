#!/usr/bin/env bash
# Usage: script/measure_dashboard.sh CHECKOUT_DIR [PORT=3999] [RUNS=6]
# Boots CHECKOUT_DIR in development, logs in as BigCo's first admin, GETs /dashboard
# RUNS times, aborting on any non-200. Needs `npm install && npm run build` done in CHECKOUT_DIR first.
# (run 1 = cold, discarded from medians). Prints no row data.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); DIR=$(cd "$1" && pwd); PORT=${2:-3999}; RUNS=${3:-6}
LOG="$DIR/log/development.log"; JAR=$(mktemp)
cd "$DIR"
MEASURE_OUT="$JAR.out" RUBYOPT="-r$HERE/sql_count.rb" bin/rails server -p "$PORT" -P "$JAR.pid" >/dev/null 2>&1 &
trap 'kill "$(cat "$JAR.pid")" 2>/dev/null || true; rm -f "$JAR" "$JAR.pid"' EXIT
for t in $(seq 60); do curl -sf "localhost:$PORT/up" >/dev/null && break; [ "$t" = 60 ] && { echo "server did not come up" >&2; exit 1; }; sleep 1; done
ADMIN=$(psql assessments_export_takehome_development -Atc "select id from company_admins where company_id=1 order by id limit 1")
TOKEN=$(curl -s -c "$JAR" "localhost:$PORT/session/new" | grep -o 'name="authenticity_token" value="[^"]*"' | sed -n '1s/.*value="//;1s/"$//p')
curl -s -b "$JAR" -c "$JAR" -o /dev/null --data-urlencode "authenticity_token=$TOKEN" -d "company_admin_id=$ADMIN" "localhost:$PORT/session"
rm -f "$JAR.out"  # drop login requests; keep only dashboard lines
for i in $(seq "$RUNS"); do
  curl -s -b "$JAR" -o /dev/null -w "run $i curl_time_total=%{time_total} http=%{http_code}\n" "localhost:$PORT/dashboard" | tee -a "$JAR.curl"
  grep -q "run $i .* http=200" "$JAR.curl" || { echo "run $i did not return 200; aborting" >&2; exit 1; }
done
sleep 1
echo "per-request (status total_ms views_ms activerecord_ms gc_ms allocations queries), run 1 = cold:"; cat "$JAR.out"
med() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
col() { tail -n +2 "$JAR.out" | cut -d' ' -f"$1" | med; }
echo "MEDIAN warm: total_ms=$(col 2) views_ms=$(col 3) activerecord_ms=$(col 4) gc_ms=$(col 5) allocations=$(col 6) queries=$(col 7) curl_s=$(tail -n +2 "$JAR.curl" | sed 's/.*total=\([0-9.]*\).*/\1/' | med)"
rm -f "$JAR.curl" "$JAR.out"
