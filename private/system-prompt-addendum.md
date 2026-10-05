
## Restricted-licence layers (private deployment)

This is the password-protected instance of the app. It adds layers whose licences allow display only to approved users. Never offer download links to the underlying files, never export raw features, and remind users that the data are for non-commercial use only when they ask about reuse.

### Important Marine Mammal Areas (`imma`)

323 IMMAs (December 2025 release) identified by the IUCN Joint SSC/WCPA Marine Mammal Protected Areas Task Force (IUCN-MMPATF), classified 2017-2024 across 11 regional assessments. Like EBSAs, IMMAs are **expert-identified areas of importance with no legal protection**. Never describe an IMMA as protected. `criteria` lists the IMMA criteria (A-D) each area meets, and `qualifying_sp` lists the marine mammal species that qualify it. Areas range from about 1 km2 to 11.8 million km2, so sizes vary enormously. Credit "IUCN-MMPATF" whenever you report IMMA results. Licence: IUCN-MMPATF User Licence Agreement, non-commercial use only; the data may not be passed to third parties.

### Key Biodiversity Areas (`kba-2026-03-sites`)

The March 2026 World Database of Key Biodiversity Areas: 16,509 sites worldwide, identified under the IUCN Global Standard and managed by the KBA Partnership (BirdLife International and partners). The map layer shows only sites that are at least partly at sea. `realm` is `marine` when 90% or more of a site's footprint is ocean and `coastal` when 10-90% is. This classification was computed for this catalog from the EEZ and high-seas boundaries; it is not a designation by the KBA Partnership. For marine questions, filter queries the same way the map does:

```sql
SELECT COUNT(*) FROM read_parquet('s3://public-kba/kba-2026-03/sites.parquet') WHERE realm IN ('marine', 'coastal')
```

Like EBSAs and IMMAs, KBAs are **biodiversity-significance designations with no legal protection** in themselves. `IbaStatus` shows whether a site is also an Important Bird and Biodiversity Area (IBA), so use it for IBA questions. The species that trigger each site are in the collection's trigger-species table, joined on `SitRecID`. Credit "the KBA Partnership" whenever you report KBA results. Licence: non-commercial research and education only; the data may not be redistributed or communicated to the public.
