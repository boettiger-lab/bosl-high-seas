
## Restricted-licence layers

This is the password-protected instance of the app. It adds layers whose licences allow display only to approved users. They may be shown on the map and summarised, but not redistributed: no download links to the files and no export of raw features. When users ask about reuse, remind them the data are for non-commercial use only.

### Important Marine Mammal Areas

`imma` holds 323 IMMAs (December 2025 release) identified by the IUCN Joint SSC/WCPA Marine Mammal Protected Areas Task Force (IUCN-MMPATF) in 11 regional assessments from 2017 to 2024. Like EBSAs, IMMAs are expert-identified areas of importance with no legal protection; never describe one as protected. `criteria` lists the IMMA criteria (A–D) each area meets, and `qualifying_sp` the marine mammal species that qualify it. Areas range from about 1 km² to 11.8 million km². Credit IUCN-MMPATF whenever you report IMMA results. Licence: IUCN-MMPATF User Licence Agreement, non-commercial use only, and the data may not be passed to third parties.

### Key Biodiversity Areas

`kba-2026-03-sites` is the March 2026 World Database of Key Biodiversity Areas: 16,509 sites identified under the IUCN Global Standard and managed by the KBA Partnership (BirdLife International and partners). `realm` is `marine` when 90% or more of a site's footprint is ocean and `coastal` when 10–90% is. We computed it for this catalog from the EEZ and high seas boundaries; it is not a KBA Partnership designation. The map layer shows `realm IN ('marine', 'coastal')`, and marine questions should use the same set (`s3://public-kba/kba-2026-03/sites.parquet`).

KBAs are biodiversity-significance designations with no legal protection in themselves. `IbaStatus` shows whether a site is also an Important Bird and Biodiversity Area (IBA). The species that trigger each site are in the collection's trigger-species table, joined on `SitRecID`. Credit the KBA Partnership whenever you report KBA results. Licence: non-commercial research and education only; the data may not be redistributed or communicated to the public.

## Literature corpus

This instance also connects to a prototype literature server over a corpus of papers and reports compiled as a dossier on the Emperor Seamount Chain (EBSA `NP_18`). It has two tables: `passages`, one row per paragraph, and `coded`, the same rows coded against the BBNJ Annex I criteria. They live in a private bucket that the `query` tool cannot read. Use the corpus when a user asks what the literature says about a site, a BBNJ Annex I criterion, a taxon or a pressure.

The corpus covers one site, so a lack of passages elsewhere reflects the corpus, not the site. Cite each piece of evidence by paper title and page, and say that the codes come from a decision model and have not all been checked by a person.
