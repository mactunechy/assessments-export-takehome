# assessments-export-takehome

Rails take-home: company-scoped CSV export, dashboard performance fix, and status normalization plan.

Work in progress.

## Legacy baseline: defects are intentional

The dashboard, export, score, filters and logging deliberately contain defects (cross-tenant export, N+1 dashboard, wrong score, bad filters, sensitive logging). Each is marked `# legacy: fixed in #N`; later issues fix them. Run `git diff legacy-baseline` to see the fixes.
