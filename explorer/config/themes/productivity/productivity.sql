-- Productivity pillar, one EBSA (the selected unit, {{ID}}).
-- This is productivity-all.sql filtered to one unit, so its numbers are identical to the
-- all-units rows for the selected unit by construction. Scores need every unit, so a live run
-- costs as much as the all-units query; the app normally reads precomputed rows.
SELECT * EXCLUDE (id) FROM (
-- Productivity pillar, all EBSAs. Unit = the EBSA's distinct H3 res-6 cells (~36 km²).
-- One row per (id, variable). pct = mid-rank percentile (0-100) among EBSAs with data,
-- higher = more productive. pillar_score = mean pct (PROVISIONAL).
WITH u AS MATERIALIZED (
  SELECT id, h0, h6, h3_cell_area(h6, 'km^2') AS a FROM (
    SELECT DISTINCT GLOBAL_ID AS id, h0, h6
    FROM read_parquet('s3://public-high-seas/ebsa-2023/hex/h0=*/data_0.parquet'))
),
units AS (SELECT id, SUM(a) AS area FROM u GROUP BY id),
cells AS (SELECT DISTINCT h0, h6 FROM u),
-- Phytoplankton carbon, depth mean, 2000-2020 baseline (Bio-ORACLE v3, res-6), area-weighted.
phyc AS (
  SELECT u.id, SUM(u.a * p.phyc_mean) / SUM(u.a) AS v
  FROM read_parquet('s3://public-bio-oracle/depthmean/phyc-mean/hex/h0=*/data_0.parquet') p
  JOIN u ON p.h0 = u.h0 AND p.h6 = u.h6
  WHERE NOT isnan(p.phyc_mean)
  GROUP BY u.id
),
-- Particulate organic carbon flux to the seafloor (NEMO-MEDUSA, 2006-2015 mean, res-6), area-weighted.
flux AS (
  SELECT u.id, SUM(u.a * f.flux_avg) / SUM(u.a) AS v
  FROM read_parquet('s3://public-high-seas/seafloor-carbon-flux/avg/hex/h0=*/data_0.parquet') f
  JOIN u ON f.h0 = u.h0 AND f.h6 = u.h6
  WHERE NOT isnan(f.flux_avg)
  GROUP BY u.id
),
vals AS (
  SELECT n.id, 'phyc_mean' AS variable, 'Mean phytoplankton carbon' AS label,
         phyc.v AS value, 'mmol/m³' AS unit, 'num2' AS fmt, 'log' AS scale, 1 AS dir
  FROM units n LEFT JOIN phyc USING (id)
  UNION ALL
  SELECT n.id, 'carbon_flux', 'Mean carbon flux to the seafloor',
         flux.v, 'mmol C/m²/day', 'num2', 'log', 1
  FROM units n LEFT JOIN flux USING (id)
),
-- Score: mid-rank percentile, 0-100, among EBSAs with data. Direction is applied first, so
-- higher is always better for the pillar. Tied values share the midpoint of their rank range.
ranked AS (
  SELECT *, CASE WHEN value IS NULL THEN NULL
                 ELSE ROUND(100 * ((RANK() OVER w - 1) + (COUNT(*) OVER w - 1)) / 2.0
                            / NULLIF(COUNT(*) OVER (PARTITION BY variable, value IS NULL) - 1, 0), 1)
            END AS pct
  FROM vals
  WINDOW w AS (PARTITION BY variable, value IS NULL ORDER BY dir * value)
)
SELECT id, variable, label, value, unit, fmt, scale, dir, pct,
       ROUND(AVG(pct) OVER (PARTITION BY id), 1) AS pillar_score
FROM ranked
ORDER BY id, variable
) WHERE id = '{{ID}}'
