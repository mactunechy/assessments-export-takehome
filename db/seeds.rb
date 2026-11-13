# Large, messy, fake dataset via set-based SQL. SEED_SCALE multiplies volume (default 1).
# Default: BigCo 100k + OtherCo 80k + 5 mid x 10k + 100 small (100-1000) ~= 285k assessments.
# Reruns wipe and reload (db:reset safe). Emails all use example.test.
scale = (ENV["SEED_SCALE"] || 1).to_f
conn = ActiveRecord::Base.connection
q = ->(sql) { conn.execute(sql) }

q.("TRUNCATE assessments, employees, company_admins, companies RESTART IDENTITY CASCADE")

ActiveRecord::Base.transaction do
  q.(<<~SQL)
    CREATE TEMP TABLE plan ON COMMIT DROP AS
    SELECT id, name, GREATEST(1, CEIL(target * #{scale}))::int AS target FROM (
      SELECT 1 AS id, 'BigCo' AS name, 100000 AS target
      UNION ALL SELECT 2, 'OtherCo', 80000
      UNION ALL SELECT g + 2, 'MidCo ' || g, 10000 FROM generate_series(1, 5) g
      UNION ALL SELECT g + 7, 'SmallCo ' || g, 100 + (random() * 900)::int FROM generate_series(1, 100) g
    ) t
  SQL

  q.(<<~SQL)
    INSERT INTO companies (id, name, created_at, updated_at)
    SELECT id, name, now() - interval '3 years', now() FROM plan
  SQL

  # 2 admins per company
  q.(<<~SQL)
    INSERT INTO company_admins (company_id, email, created_at, updated_at)
    SELECT p.id, 'admin' || a || '.company' || p.id || '@example.test', now(), now()
    FROM plan p, generate_series(1, 2) a
  SQL

  # employees: target/50, at least 3
  q.(<<~SQL)
    INSERT INTO employees (company_id, name, email, created_at, updated_at)
    SELECT p.id, 'Employee ' || p.id || '-' || e, 'emp' || e || '.company' || p.id || '@example.test',
           now() - interval '2 years', now()
    FROM plan p, LATERAL generate_series(1, GREATEST(3, p.target / 50)) e
  SQL

  q.(<<~SQL)
    CREATE TEMP TABLE emp ON COMMIT DROP AS
    SELECT id, email, company_id,
           row_number() OVER (PARTITION BY company_id ORDER BY id) - 1 AS rn,
           count(*) OVER (PARTITION BY company_id) AS n
    FROM employees
  SQL

  # Raw SQL on purpose: this bypasses the model so the seed data contains the messy legacy
  # statuses (complete/comp/done, NULL, '', 'n/a') that the app and backfill must handle.
  q.(<<~SQL)
    INSERT INTO assessments (company_id, employee_id, employee_email, status, responses_json, created_at, updated_at)
    SELECT p.id, e.id, e.email,
      (ARRAY['completed','completed','completed','complete','comp','done','pending','pending',
             'in_progress','needs_follow_up','archived',NULL,'','n/a'])[1 + (random() * 13)::int],
      CASE g % 500
        WHEN 1 THEN '{"version":1,"answers":[]}'::jsonb
        WHEN 2 THEN '{"version":1,"answers":[{"q":"neck_pain","type":"scale","value":null},{"q":"back_pain","type":"scale","value":null}]}'::jsonb
        WHEN 3 THEN '{"version":1,"answers":[{"q":"neck_pain","type":"scale","value":"n/a"},{"q":"back_pain","type":"scale","value":3}]}'::jsonb
        ELSE jsonb_build_object('version', 1, 'answers', jsonb_build_array(
          jsonb_build_object('q','neck_pain','type','scale','value',1 + (random()*4)::int),
          jsonb_build_object('q','back_pain','type','scale','value',1 + (random()*4)::int),
          jsonb_build_object('q','eye_strain','type','scale','value',1 + (random()*4)::int),
          jsonb_build_object('q','wrist_pain','type','scale','value',1 + (random()*4)::int),
          jsonb_build_object('q','breaks','type','choice','value',(ARRAY['yes','no','n/a'])[1 + (random()*2)::int]),
          jsonb_build_object('q','notes','type','text','value',
            (ARRAY['Desk is too low.','Monitor glare in the afternoon.','No issues.','Chair needs adjusting.',
                   'Shoulders sore after long calls.'])[1 + (random()*4)::int])))
      END,
      ts, ts
    FROM plan p
    CROSS JOIN LATERAL generate_series(1, p.target) g
    -- g * 0 makes the subquery depend on the row, so random() runs per row (not hoisted once)
    CROSS JOIN LATERAL (SELECT now() - (random() * 730 + g * 0) * interval '1 day' AS ts) t
    JOIN emp e ON e.company_id = p.id AND e.rn = g % e.n
  SQL

  %w[companies company_admins employees assessments].each do |t|
    q.("SELECT setval(pg_get_serial_sequence('#{t}', 'id'), (SELECT max(id) FROM #{t}))")
  end
end
