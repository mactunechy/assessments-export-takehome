namespace :assessments do
  desc "Normalize legacy Assessment#status. Dry run by default; real run: assessments:backfill_status[false,5000,0.2]"
  task :backfill_status, [:dry_run, :batch, :sleep] => :environment do |_, args|
    dry_run = args[:dry_run].to_s.downcase != "false"
    batch   = (args[:batch] || 5000).to_i
    pause   = (args[:sleep] || 0.2).to_f
    abort "batch must be > 0" unless batch.positive?

    db = Assessment.connection
    q  = ->(v) { db.quote(v) }
    # Mapping on lower(btrim(status)), generated from the model constants.
    # NULL and ""/"n/a" -> pending (original kept in legacy_status); the rest identity or alias.
    known = Assessment::STATUSES + Assessment::LEGACY_ALIASES.keys + ["", "n/a"]
    norm  = "lower(btrim(status))"
    target = "CASE coalesce(#{norm}, '')" \
      "#{Assessment::LEGACY_ALIASES.map { |k, v| " WHEN #{q[k]} THEN #{q[v]}" }.join}" \
      "#{Assessment::STATUSES.map { |s| " WHEN #{q[s]} THEN #{q[s]}" }.join}" \
      " WHEN '' THEN 'pending' WHEN 'n/a' THEN 'pending' ELSE status END"

    # Counts per normalized value (NULL stays NULL). Prints status values only, never row data.
    rows = db.select_rows("SELECT #{norm}, count(*) FROM assessments GROUP BY 1 ORDER BY 1")
    unknown = rows.reject { |v, _| v.nil? || known.include?(v) }
    puts "#{dry_run ? 'DRY RUN' : 'REAL RUN'}: normalized value -> count -> target"
    rows.each do |v, n|
      t = v.nil? ? "pending" : (known.include?(v) ? db.select_value("SELECT #{target} FROM (SELECT #{q[v]}::text AS status) s") : "UNKNOWN")
      puts format("  %-20s %8d -> %s", v.inspect, n, t)
    end
    if unknown.any?
      puts "ABORT: #{unknown.size} unknown value(s), nothing changed:"
      unknown.each { |v, n| puts "  #{v.inspect}: #{n}" }
      exit 1
    end
    if dry_run
      puts "Dry run only; nothing changed. Real run: bin/rails 'assessments:backfill_status[false]'"
      next
    end

    # Real run: id-range batches, one short transaction each. Idempotent and resumable:
    # canonical rows are skipped, so rerunning after an interruption continues where it stopped.
    # update_all issues raw SQL, so updated_at is not touched.
    min, max = Assessment.pick("min(id)", "max(id)")
    (min.to_i).step(max.to_i, batch) do |lo|
      n = Assessment.transaction do
        Assessment.where(id: lo...(lo + batch))
                  .where("status IS NULL OR status NOT IN (#{Assessment::STATUSES.map(&q).join(',')})")
                  .update_all("legacy_status = status, status = #{target}")
      end
      puts "ids #{lo}...#{lo + batch}: #{n} updated"
      sleep pause
    end
  end
end
