-- Biodiversity pillar, one EBSA (the selected unit, {{ID}}).
-- This is biodiversity-all.sql filtered to one unit, so its numbers are identical to the
-- all-units rows for the selected unit by construction. Scores need every unit, so a live run
-- costs as much as the all-units query; the app normally reads precomputed rows.
SELECT * EXCLUDE (id) FROM (
-- Biodiversity pillar, all EBSAs. Unit = the EBSA's distinct H3 res-6 cells (~36 km²).
-- One row per (id, variable). pct = mid-rank percentile (0-100) among EBSAs with data,
-- higher = more biodiversity value. pillar_score = mean pct (PROVISIONAL).
WITH u AS MATERIALIZED (
  SELECT id, h0, h6, h3_cell_area(h6, 'km^2') AS a FROM (
    SELECT DISTINCT GLOBAL_ID AS id, h0, h6
    FROM read_parquet('s3://public-high-seas/ebsa-2023/hex/h0=*/data_0.parquet'))
),
units AS (SELECT id, SUM(a) AS area FROM u GROUP BY id),
cells AS (SELECT DISTINCT h0, h6 FROM u),
-- Mean threatened species richness (IUCN 2025 range maps, VU/EN/CR, res-5): the mapped
-- groups are amphibians, birds, mammals, reptiles and freshwater fish, so at sea it counts
-- seabirds and marine mammals, not marine fish or invertebrates.
thr AS (
  SELECT u.id, SUM(u.a * r.combined_thr_sr) / SUM(u.a) AS v
  FROM u JOIN read_parquet('s3://public-iucn/hex/combined_thr_sr/h0=*/data_0.parquet') r
    ON r.h0 = u.h0 AND r.h5 = h3_cell_to_parent(u.h6, 5)
  WHERE NOT isnan(r.combined_thr_sr)
  GROUP BY u.id
),
-- MegaMove Important Marine Megafauna Areas (IMMegAs; 1-degree source grid, res-4 hex).
imm AS (
  SELECT DISTINCT h0, h4, Taxon
  FROM read_parquet('s3://public-high-seas/megamove/immegas/hex/h0=*/data_0.parquet')
),
imm_share AS (
  SELECT u.id, SUM(u.a) FILTER (WHERE i.h4 IS NOT NULL) AS v
  FROM u LEFT JOIN (SELECT h0, h4 FROM imm WHERE Taxon = 'All taxa') i
    ON i.h0 = u.h0 AND i.h4 = h3_cell_to_parent(u.h6, 4)
  GROUP BY u.id
),
imm_taxa AS (
  SELECT u.id, COUNT(DISTINCT i.Taxon) AS v
  FROM u JOIN imm i ON i.h0 = u.h0 AND i.h4 = h3_cell_to_parent(u.h6, 4)
  WHERE i.Taxon <> 'All taxa'
  GROUP BY u.id
),
vals AS (
  SELECT n.id, 'threatened_richness' AS variable, 'Mean threatened species richness' AS label,
         thr.v AS value, 'species' AS unit, 'num1' AS fmt, 'linear' AS scale, 1 AS dir
  FROM units n LEFT JOIN thr USING (id)
  UNION ALL
  SELECT n.id, 'immega_share', 'Area in Important Marine Megafauna Areas',
         COALESCE(imm_share.v, 0) / n.area, 'share', 'pct', 'linear', 1
  FROM units n LEFT JOIN imm_share USING (id)
  UNION ALL
  SELECT n.id, 'immega_taxa', 'Megafauna groups with an important area',
         COALESCE(imm_taxa.v, 0), 'groups', 'int', 'linear', 1
  FROM units n LEFT JOIN imm_taxa USING (id)
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
