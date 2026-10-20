-- Pressures pillar, one EBSA (the selected unit, {{ID}}).
-- This is pressures-all.sql filtered to one unit, so its numbers are identical to the
-- all-units rows for the selected unit by construction. Scores need every unit, so a live run
-- costs as much as the all-units query; the app normally reads precomputed rows.
SELECT * EXCLUDE (id) FROM (
-- Pressures pillar, all EBSAs. Unit = the EBSA's distinct H3 res-6 cells (~36 km²).
-- One row per (id, variable). dir = -1: less pressure scores higher.
-- pct = mid-rank percentile (0-100) among EBSAs with data. pillar_score = mean pct (PROVISIONAL).
WITH u AS MATERIALIZED (
  SELECT id, h0, h6, h3_cell_area(h6, 'km^2') AS a FROM (
    SELECT DISTINCT GLOBAL_ID AS id, h0, h6
    FROM read_parquet('s3://public-high-seas/ebsa-2023/hex/h0=*/data_0.parquet'))
),
units AS (SELECT id, SUM(a) AS area FROM u GROUP BY id),
cells AS (SELECT DISTINCT h0, h6 FROM u),
-- Apparent fishing effort 2024 (Global Fishing Watch v3, all gears, res-6), hours per 1,000 km².
fish AS (
  SELECT u.id, SUM(f.fishing_hours) AS v
  FROM read_parquet('s3://public-gfw/gfw-fishing-effort/hex/h0=*/*.parquet') f
  JOIN u ON f.h0 = u.h0 AND f.h6::UBIGINT = u.h6
  WHERE f.year = 2024
  GROUP BY u.id
),
-- Vessel density (IMF / World Bank global layer, AIS positions, Jan 2015 - Feb 2021, res-8 summed to res-6).
-- Coverage stops near ±85°, so polar cells have no value and do not enter the mean.
ship_c AS (
  SELECT s.h0, s.h6, SUM(s.ais_positions) AS n
  FROM read_parquet('s3://public-high-seas/ship-density/global/hex/h0=*/data_0.parquet') s
  SEMI JOIN cells c ON s.h0 = c.h0 AND s.h6 = c.h6
  GROUP BY s.h0, s.h6
),
ship AS (
  SELECT u.id, SUM(s.n) / SUM(u.a) AS v
  FROM u JOIN ship_c s ON s.h0 = u.h0 AND s.h6 = u.h6
  GROUP BY u.id
),
vals AS (
  SELECT n.id, 'fishing_hours' AS variable, 'Fishing effort in 2024' AS label,
         1000 * COALESCE(fish.v, 0) / n.area AS value, 'hours per 1,000 km²' AS unit,
         'num1' AS fmt, 'log' AS scale, -1 AS dir
  FROM units n LEFT JOIN fish USING (id)
  UNION ALL
  SELECT n.id, 'ship_density', 'Vessel density',
         ship.v, 'AIS positions per km²', 'compact', 'log', -1
  FROM units n LEFT JOIN ship USING (id)
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
