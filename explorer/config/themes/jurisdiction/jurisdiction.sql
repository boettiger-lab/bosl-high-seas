-- Jurisdiction, one EBSA (the selected unit, {{ID}}). This is jurisdiction-all.sql filtered
-- to one unit, so its numbers are identical to the all-units rows for that unit.
SELECT * EXCLUDE (id) FROM (
-- Jurisdiction, all EBSAs. Unit = the EBSA's H3 res-6 cells (~36 km²), from the res-8 hex.
-- One row per (id, zone). A cell inside an EEZ (EEZ v12) counts for that EEZ's primary
-- sovereign (ISO_SOV1), so overseas territories count for their sovereign. A cell in no EEZ
-- is 'High seas' when it lies within two res-4 rings of the World High Seas v2 mask or north
-- of 86°N (the res-4 mask leaves a gap at the pole); otherwise it is 'Outside any EEZ'
-- (land, estuaries and inland seas such as the Caspian, which EEZ v12 does not cover).
-- abnj_share = share of the EBSA's area on the high seas, repeated on each row.
WITH u AS MATERIALIZED (
  SELECT DISTINCT GLOBAL_ID AS id, h0, h6
  FROM read_parquet('s3://public-high-seas/ebsa-2023/hex/h0=*/data_0.parquet')
),
eez AS (
  SELECT e.h0, e.h6, ANY_VALUE(e.SOVEREIGN1) AS sovereign, ANY_VALUE(e.ISO_SOV1) AS iso3
  FROM read_parquet('s3://public-high-seas/iho/eez/hex/h0=*/data_00.parquet') e
  SEMI JOIN u ON e.h0 = u.h0 AND e.h6 = u.h6
  GROUP BY e.h0, e.h6
),
hs AS (
  SELECT DISTINCT d AS h4
  FROM read_parquet('s3://public-high-seas/iho/high-seas/hex/h0=*/data_00.parquet'),
       UNNEST(h3_grid_disk(h4, 2)) AS t(d)
),
cells AS (
  SELECT u.id, h3_cell_area(u.h6, 'km^2') AS a,
         CASE WHEN eez.h6 IS NOT NULL THEN eez.sovereign
              WHEN hs.h4 IS NOT NULL OR h3_cell_to_lat(u.h6) > 86 THEN 'High seas'
              ELSE 'Outside any EEZ' END AS zone,
         eez.iso3
  FROM u
  LEFT JOIN eez ON eez.h0 = u.h0 AND eez.h6 = u.h6
  LEFT JOIN hs ON hs.h4 = h3_cell_to_parent(u.h6, 4)
),
by_zone AS (
  SELECT id, zone, ANY_VALUE(iso3) AS iso3, SUM(a) AS area_km2 FROM cells GROUP BY id, zone
),
shares AS (
  SELECT *, area_km2 / SUM(area_km2) OVER (PARTITION BY id) AS share FROM by_zone
)
SELECT id, zone, iso3, area_km2, share,
       COALESCE(SUM(share) FILTER (WHERE zone = 'High seas') OVER (PARTITION BY id), 0) AS abnj_share,
       SUM(area_km2) OVER (PARTITION BY id) AS ebsa_km2,
       COUNT(*) FILTER (WHERE zone NOT IN ('High seas', 'Outside any EEZ')) OVER (PARTITION BY id) AS n_states
FROM shares
ORDER BY id, share DESC
) WHERE id = '{{ID}}'
