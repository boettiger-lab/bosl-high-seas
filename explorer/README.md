# High Seas EBSA Explorer

A no-LLM companion to the High Seas map and chat app, built on
[glen-charts](https://github.com/SchmidtDSE/glen-charts) (pinned in `index.html`, currently
v0.2.4) in the style of the Blue Boundaries coastal ecoregion explorer. It ranks every
Ecologically or Biologically Significant Marine Area (EBSA) on five pillars and lets the
reader re-weight them. It is served at <https://high-seas.nrp-nautilus.io/explorer/>.

**Status: provisional.** The pillars loosely follow the BBNJ Agreement's Annex I indicative
criteria, but which variables belong to each pillar, their direction and the weights are a
first cut for discussion. Nobody has yet agreed on them.

This directory holds only configuration: `index.html`, `app.css`, `config/app.json`, one
theme folder per pillar plus the jurisdiction overview, the SQL, and precomputed `data/`.
Do not write JavaScript here. Features go into glen-charts.

## Units

The unit is the EBSA, from the `ebsa-2023` collection (336 sites, all 15 CBD regional
workshops). The id is `GLOBAL_ID` (a string such as `WC_13`, the Sargasso Sea), and the
map draws `ebsa-2023.pmtiles`.

- EBSAs total about 80 M km², and the largest is 11 M km². At the catalog's res-8 that is
  over 100 M cells, so every query works on each EBSA's distinct **res-6 cells** (about
  36 km², 2.3 M cells in all). The 13 EBSAs smaller than about 40 km² are one or a few
  cells, so their shares are coarse.
- EBSAs overlap one another. Each is scored on its own cells, so a cell can count for
  several EBSAs.
- Some EBSA names in the source file have broken accents (e.g. "2les des Sept Frbres").
  This is upstream in the 2023 compilation.

## Tokens

| Token | Meaning |
|---|---|
| `{{ID}}` | EBSA `GLOBAL_ID`, quoted in the SQL as `'{{ID}}'` |
| `{{AOI}}` | The EBSA's res-8 cells (`aoi` in `app.json`) |

There are no params. The all-units SQL uses no tokens.

## Themes and scores

Each theme has two queries: `<t>-all.sql` returns one row per (id, variable) for every
EBSA, with columns `id, variable, label, value, unit, fmt, scale, dir, pct, pillar_score`,
and `<t>.sql` is the same SQL filtered to `{{ID}}`. The app reads the precomputed
all-units rows.

- **`pct`** is the mid-rank percentile, 0–100, among the EBSAs with data for that
  variable. Direction is applied first, so higher is always better for the pillar, and
  tied values share the midpoint of their rank range. Ties matter here: most EBSAs have no
  vent, no trench and no no-take area.
- **`pillar_score`** is the plain mean of the EBSA's `pct` values.
- **`value`** is NULL only where the source has no data (e.g. vessel density north of
  85°). Absence of a mapped feature is a measured 0.

| Pillar | Variable | Higher pct when | Annex I criteria |
|---|---|---|---|
| Biodiversity | Mean threatened species richness (IUCN 2025; seabirds and marine mammals at sea) | more species | (d), (e) |
| | Area in Important Marine Megafauna Areas (MegaMove, all taxa) | more area | (c), (m) |
| | Megafauna groups with an important area (0–8) | more groups | (c), (i) |
| Seafloor habitats | Area on seamounts or guyots (Harris et al. 2014) | more | (a), (b), (g) |
| | Area on ridges or rift valleys | more | (a), (n) |
| | Area in trenches or hadal zone | more | (a), (b) |
| | Active hydrothermal vents (InterRidge v3.4) | more | (a), (b), (g) |
| Productivity | Mean phytoplankton carbon (Bio-ORACLE v3, depth mean) | more | (i) |
| | Mean carbon flux to the seafloor (NEMO-MEDUSA 2006–2015) | more | (i), (n) |
| Pressures | Fishing effort in 2024 per 1,000 km² (GFW) | less | (q) |
| | Vessel density, AIS positions per km² (IMF / World Bank, 2015–2021) | less | (q) |
| Protection | Area in marine protected areas (WDPA, not Proposed) | more | (v) |
| | Area in fully no-take protected areas | more | (v) |
| | Area in bottom-fishing closures (FAO VME) | more | (v) |

Two directions are judgment calls the scoring panel can flip. Pressures score low
pressure as better, as in the coastal explorer; an argument for urgency would reverse it.
Protection scores existing measures as better (criterion v); a gap analysis would reverse it.

## Jurisdiction (overview card)

`config/themes/jurisdiction/` is shown on every profile. It splits each EBSA's cells by
EEZ v12 sovereign (`ISO_SOV1`), "High seas" or "Outside any EEZ". A cell in no EEZ is high
seas when it is within two res-4 rings of the World High Seas v2 mask, or north of 86°N,
where the res-4 mask leaves a gap at the pole. The remainder is land, estuaries and inland
seas such as the Caspian. `abnj_share` is the high-seas share. Of the 80 M km², about 52 M
are high seas, 29 M are in EEZs and 1 M is outside both.

The leaderboard's **High seas** view keeps EBSAs with `abnj_share >= 0.5` and recomputes
the percentiles among them.

## Licences

The precomputed files are per-EBSA summaries, not the source data. Several sources carry
terms beyond attribution: WDPA (no redistribution of the data), IUCN range maps
(non-commercial), InterRidge vents (CC-BY-NC-SA), GFW (CC-BY-NC) and the FAO VME and RFMO
layers (CC-BY-SA-3.0-IGO). The exported report cites each dataset from its STAC record.

## Updating

```bash
# after changing any SQL (results take a few minutes per pillar on the MCP server)
npx github:SchmidtDSE/glen-charts#v0.2.4 precompute --site explorer lists
npx github:SchmidtDSE/glen-charts#v0.2.4 precompute --site explorer results
npx github:SchmidtDSE/glen-charts#v0.2.4 precompute --site explorer sources
git add explorer && git commit && git push      # then restart the deployment
```

The `<t>.sql` files are `<t>-all.sql` wrapped in `SELECT * EXCLUDE (id) FROM (…) WHERE id = '{{ID}}'`.
Regenerate them whenever an all-units file changes, so the two never disagree.
