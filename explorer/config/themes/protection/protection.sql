-- Protection pillar, one EBSA (the selected unit, {{ID}}).
-- This is protection-all.sql filtered to one unit, so its numbers are identical to the
-- all-units rows for the selected unit by construction. Scores need every unit, so a live run
-- costs as much as the all-units query; the app normally reads precomputed rows.
SELECT * EXCLUDE (id) FROM (
-- Protection pillar, all EBSAs. Unit = the EBSA's distinct H3 res-6 cells (~36 km²).
-- One row per (id, variable). pct = mid-rank percentile (0-100) among EBSAs with data,
-- higher = more of the area under existing measures. pillar_score = mean pct (PROVISIONAL).
-- Shares count distinct cells, because protected areas and closures overlap. A res-6 cell
-- counts if any part of it is covered, so shares are upper bounds for small sites.
WITH u AS MATERIALIZED (
  SELECT id, h0, h6, h3_cell_area(h6, 'km^2') AS a FROM (
    SELECT DISTINCT GLOBAL_ID AS id, h0, h6
    FROM read_parquet('s3://public-high-seas/ebsa-2023/hex/h0=*/data_0.parquet'))
),
units AS (SELECT id, SUM(a) AS area FROM u GROUP BY id),
cells AS (SELECT DISTINCT h0, h6 FROM u),
-- Marine and coastal protected areas in force (WDPA; realm Marine or Coastal, not Proposed).
mpa AS (
  SELECT DISTINCT w.h0, h3_cell_to_parent(w.h8, 6) AS h6, trim(w.NO_TAKE) = 'All' AS no_take
  FROM read_parquet('s3://public-wdpa/wdpa/hex/h0=*/data_0.parquet') w
  SEMI JOIN (SELECT DISTINCT h0 FROM cells) c ON w.h0 = c.h0
  WHERE w.REALM IN ('Marine', 'Coastal') AND w.STATUS <> 'Proposed'
),
mpa_c AS (SELECT h0, h6, BOOL_OR(no_take) AS no_take FROM mpa GROUP BY h0, h6),
-- Bottom-fishing closures to protect vulnerable marine ecosystems (FAO VME database, res-8).
vme AS (
  SELECT DISTINCT v.h0, v.h6
  FROM read_parquet('s3://public-high-seas/rfmo/vme/hex/h0=*/data_00.parquet') v
  SEMI JOIN cells c ON v.h0 = c.h0 AND v.h6 = c.h6
),
cov AS (
  SELECT u.id,
         COALESCE(SUM(u.a) FILTER (WHERE m.h6 IS NOT NULL), 0) AS mpa,
         COALESCE(SUM(u.a) FILTER (WHERE m.no_take), 0) AS no_take,
         COALESCE(SUM(u.a) FILTER (WHERE v.h6 IS NOT NULL), 0) AS vme
  FROM u
  LEFT JOIN mpa_c m ON m.h0 = u.h0 AND m.h6 = u.h6
  LEFT JOIN vme v ON v.h0 = u.h0 AND v.h6 = u.h6
  GROUP BY u.id
),
vals AS (
  SELECT n.id, 'mpa_share' AS variable, 'Area in marine protected areas' AS label,
         c.mpa / n.area AS value, 'share' AS unit, 'pct' AS fmt, 'linear' AS scale, 1 AS dir
  FROM units n JOIN cov c USING (id)
  UNION ALL
  SELECT n.id, 'no_take_share', 'Area in fully no-take protected areas',
         c.no_take / n.area, 'share', 'pct', 'linear', 1
  FROM units n JOIN cov c USING (id)
  UNION ALL
  SELECT n.id, 'vme_share', 'Area in bottom-fishing closures',
         c.vme / n.area, 'share', 'pct', 'linear', 1
  FROM units n JOIN cov c USING (id)
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
