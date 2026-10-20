-- Seafloor habitats pillar, one EBSA (the selected unit, {{ID}}).
-- This is seafloor-all.sql filtered to one unit, so its numbers are identical to the
-- all-units rows for the selected unit by construction. Scores need every unit, so a live run
-- costs as much as the all-units query; the app normally reads precomputed rows.
SELECT * EXCLUDE (id) FROM (
-- Seafloor habitats pillar, all EBSAs. Unit = the EBSA's distinct H3 res-6 cells (~36 km²).
-- One row per (id, variable). pct = mid-rank percentile (0-100) among EBSAs with data,
-- higher = more of the habitat. pillar_score = mean pct (PROVISIONAL).
WITH u AS MATERIALIZED (
  SELECT id, h0, h6, h3_cell_area(h6, 'km^2') AS a FROM (
    SELECT DISTINCT GLOBAL_ID AS id, h0, h6
    FROM read_parquet('s3://public-high-seas/ebsa-2023/hex/h0=*/data_0.parquet'))
),
units AS (SELECT id, SUM(a) AS area FROM u GROUP BY id),
cells AS (SELECT DISTINCT h0, h6 FROM u),
-- Seafloor geomorphology (Harris et al. 2014, res-6). Feature layers overlap, so each share
-- counts distinct cells carrying any of the named feature types.
geo AS (
  SELECT g.h0, g.h6,
         BOOL_OR(g.feature_type IN ('Seamounts', 'Guyots')) AS seamount,
         BOOL_OR(g.feature_type IN ('Trenches', 'Hadal')) AS trench,
         BOOL_OR(g.feature_type IN ('Ridges', 'Spreading_ridges', 'Rift_valleys')) AS ridge
  FROM read_parquet('s3://public-high-seas/seafloor-geomorphology/hex/h0=*/data_0.parquet') g
  SEMI JOIN cells c ON g.h0 = c.h0 AND g.h6 = c.h6
  GROUP BY g.h0, g.h6
),
geo_u AS (
  SELECT u.id,
         COALESCE(SUM(u.a) FILTER (WHERE geo.seamount), 0) AS seamount,
         COALESCE(SUM(u.a) FILTER (WHERE geo.trench), 0) AS trench,
         COALESCE(SUM(u.a) FILTER (WHERE geo.ridge), 0) AS ridge
  FROM u LEFT JOIN geo ON geo.h0 = u.h0 AND geo.h6 = u.h6
  GROUP BY u.id
),
-- Active hydrothermal vents (InterRidge v3.4; confirmed or inferred), one row per vent.
vents AS (
  SELECT u.id, COUNT(DISTINCT v._cng_fid) AS v
  FROM read_parquet('s3://public-high-seas/hydrothermal-vents/hex/h0=*/data_0.parquet') v
  JOIN u ON v.h0 = u.h0 AND h3_cell_to_parent(v.h8, 6) = u.h6
  WHERE v.activity LIKE 'active%'
  GROUP BY u.id
),
vals AS (
  SELECT n.id, 'seamount_share' AS variable, 'Area on seamounts or guyots' AS label,
         g.seamount / n.area AS value, 'share' AS unit, 'pct' AS fmt, 'linear' AS scale, 1 AS dir
  FROM units n JOIN geo_u g USING (id)
  UNION ALL
  SELECT n.id, 'ridge_share', 'Area on ridges or rift valleys',
         g.ridge / n.area, 'share', 'pct', 'linear', 1
  FROM units n JOIN geo_u g USING (id)
  UNION ALL
  SELECT n.id, 'trench_share', 'Area in trenches or hadal zone',
         g.trench / n.area, 'share', 'pct', 'linear', 1
  FROM units n JOIN geo_u g USING (id)
  UNION ALL
  SELECT n.id, 'active_vents', 'Active hydrothermal vents',
         COALESCE(vents.v, 0), 'vents', 'int', 'linear', 1
  FROM units n LEFT JOIN vents USING (id)
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
