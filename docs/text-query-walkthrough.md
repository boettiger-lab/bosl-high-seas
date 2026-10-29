# Text query walkthrough

This walkthrough follows one question through the prototype literature server in the private
High Seas app:

> Is there evidence that coral communities on the Emperor seamounts recover after bottom
> trawling stops? Quote the strongest passages with paper and page.

It separates two things throughout: what the tools always do, which is fixed in the server's
code, and what the chat agent chose to do for this question, which another model or another run
might do differently. The tool calls and SQL come from the server log of 2026-10-28. The log
records each call's SQL but not the questions the agent wrote for `decide`, so the `decide`
results come from a rerun of the agent's exact SQL with an equivalent question.

## Data in the private bucket

The bucket `high-seas-lit` on rustfs holds two kinds of object.

- **Originals.** 202 PDFs in the 12 dossier section folders, with names as received. They are
  never modified.
- **Derived tables** in `derived/2026-10-27/`, as Parquet with one row per passage.

| Column | Example |
|---|---|
| `passage_id` | `e8060611aaad9434`, a hash of document, position and text |
| `doc_id` | `d63b429b61a03272`, a hash of the PDF's bytes, so identical copies collapse to one |
| `title` | "Amid fields of rubble, scars, and lost gear, signs of recovery observed on seamounts on 30- to 40-year time scales" |
| `page` | `1`, the PDF page number, not the journal page |
| `ordinal` | `0`, the passage's position in the document |
| `text` | the passage itself, here the paper's author line and the opening of its abstract |
| `n_chars` | `1214` |
| `folder`, `file`, `folders` | `8.2.3.Megafauna`, plus every folder the paper appears in |

The pilot's PyMuPDF script made the passages. It reads each PDF's text blocks, drops running
headers and footers, tables of contents and everything after the References heading, and
merges blocks into chunks of about a paragraph. The result is 14,513 passages from 186 PDFs.
The 8 scanned PDFs have no text yet. GROBID will replace this step in `text-ingest`.

There are two tables.

- **`passages`** holds the columns above.
- **`coded`** holds the same rows plus about 40 columns of answers to the preset codebook,
  described in the next section.

The server registers both as DuckDB views, so SQL can name them directly and DuckDB reads the
Parquet from rustfs as needed.

## Preset and custom questions

Jev answers questions in two ways, at different times.

**Preset questions were answered once, in advance.** Before anyone used the app, the BBNJ
codebook `codebooks/bbnj-annex1.yaml` in `bosl-high-seas` was run over all 14,513 passages, in
20 minutes for $1.53. The codebook is a fixed list of questions, and its answers are the extra
columns in `coded`. It has two passes.

- **The screen pass** runs on every passage. `content` asks whether the passage reports science
  rather than references or boilerplate. `site` chooses between a named Emperor feature, the
  Emperor chain, elsewhere in the North Pacific, another ocean, global, or none.
- **The criteria pass** runs only where `content > 0.5`. It has one yes or no question for each
  Annex I criterion from (a) to (v), plus `direction`, `evidence_type`, `strength` (0 to 3),
  `taxon`, `zone` and `pressure`.

Jev has answered nothing beyond that list. The criterion closest to the example question is (r):

```yaml
crit_r_recovery:
  type: noul
  instructions: >-
    Does this paragraph describe slow recovery after disturbance, long-lived or slow-growing
    organisms, or the resilience of the place studied?
```

**Custom questions are answered when they are asked.** Any user question that the preset columns
do not answer precisely goes to `decide`. The agent writes the questions in the same format as
the codebook, and Jev answers them for the passages the agent selects, at that moment. For the
example question an equivalent of what the agent wrote is:

```json
{
  "recovery": {
    "type": "noul",
    "instructions": "Does this paragraph report observed recovery, or signs of recovery, of corals or other bottom fauna on seamounts after bottom trawling stopped?"
  },
  "recovery_speed": {
    "type": "choice",
    "instructions": "What does this paragraph say about how fast seamount bottom communities recover from trawling?",
    "criteria": {
      "slow": "recovery is slow, takes decades or longer, or has not happened",
      "some": "some recovery or recolonisation is observed",
      "not_addressed": "recovery speed is not addressed"
    }
  }
}
```

Criterion (r) is broad: it covers slow recovery, slow growth or resilience in general. The
custom question is specific to recovery after trawling stopped. `decide` never reuses the preset
answers; it sends its own questions to Jev.

The two combine. SQL can filter on preset columns, for example
`WHERE site IN ('emperor_feature', 'emperor_chain')`, and `decide` can then ask a custom
question of the rows that remain.

## Tool behaviour

Both tools accept any DuckDB SQL. Neither tool picks a table: the SQL the agent writes names
`passages`, `coded` or a join of the two.

| | Table | Jev's role |
|---|---|---|
| `read_rows` | whatever the SQL names | none; it only returns rows, including preset answers in `coded` |
| `decide` | whatever the SQL names, which must include a text column | answers the custom questions for each row, now |

**`read_rows(sql, max_rows=20)`** always does the same thing: it runs the SQL and returns up to
50 rows, with strings cut at 500 characters.

**`decide(sql, questions, text_column="text", context_column=None, return_rows="positive",
max_return=40, include_text=False)`** always works in four steps.

1. It runs the SQL and refuses to continue if more than 400 rows come back.
2. For each row it builds a *state*: the `context_column` value (here the paper title), a blank
   line, then the text.
3. It sends one request per passage to Jev with the state and the questions, twelve at a time.
   Answers are cached by model, question and text, so a repeated question costs nothing. Jev
   returns a probability for each question rather than prose.

   | Question type | Jev returns |
   |---|---|
   | `noul` (yes or no) | P(yes) |
   | `choice` | a probability for each label |
   | `score` | the expected level on an ordered scale |

4. It returns a summary over all rows, plus the rows with the highest yes probabilities, with
   every column except the text, unless `include_text` is set.

## Filtering before Jev

`decide` takes a SQL filter and a 400-row limit so that a custom question stays interactive.
Asking Jev about every passage takes about 20 minutes and costs about $1.50. Narrowing first to
a few hundred passages, with keywords, section folders or preset columns, takes a few seconds
and costs a fraction of a cent.

The cost is recall: Jev never sees a passage the filter dropped. Nothing in the design requires
the filter. The planned `submit_decide` tool will run a custom question over the whole corpus
as a batch job of a few minutes, for questions where recall matters more than speed.

## Loading the tools in geo-agent

No change to geo-agent was needed. Since v3.36.0, an app can list several MCP servers in
`layers-input.json`. At startup geo-agent connects to each one, asks it for its tool list, and
registers every tool under its name with its description and argument schema. The model sees
`read_rows` and `decide` next to the SQL tools and calls them in the same way. Only the first
server, the main SQL server, gets special handling such as the geospatial prompts.

Adding the literature tools therefore took two changes in `bosl-high-seas`: the bump to
geo-agent v3.36.0, and a config entry that points to the private app's `/api/text-query/` route.
One gap remains. geo-agent does not pass a server's instructions to the model, so the server
appends its corpus description to each tool's description instead.

The agent's choices are steered, not enforced, by text we wrote: the tool descriptions, which
recommend a 0.7 threshold, `context_column='title'` and citation by title and page, and the
private system prompt.

## Agent choices for the example question

Every step below was the agent's choice. Only the work inside each tool call followed the fixed
behaviour above.

1. **Finding the tables.** The agent first guessed tables that do not exist (`pages`,
   `lit_passages`, `chunks`) before it found `passages`. The guesses cost a few seconds and
   calls but no Jev credit.
2. **Keyword scan.** It called `read_rows` with trawl words combined with recovery words, and
   400-character snippets.
3. **First `decide`.** It chose to narrow with words alone, on `passages`:

   ```sql
   SELECT passage_id, title, page, ordinal, text FROM passages
   WHERE (lower(text) LIKE '%trawl%' OR lower(text) LIKE '%bottom-contact%'
          OR lower(text) LIKE '%bottom contact%' OR lower(text) LIKE '%bottom fishing%')
     AND (lower(text) LIKE '%recover%' OR lower(text) LIKE '%recruit%' OR lower(text) LIKE '%regrow%'
          OR lower(text) LIKE '%recolon%' OR lower(text) LIKE '%resilien%' OR lower(text) LIKE '%reseed%'
          OR lower(text) LIKE '%regenerat%')
   ```

   The SQL returns 116 passages. The rerun with the custom questions above took 7.5 s and cost
   $0.003.

   | Measure | Result |
   |---|---|
   | `recovery` above 0.5 | 58 of 116 |
   | `recovery` above 0.7 | 48 of 116 |
   | `recovery_speed` | 45 slow, 22 some, 49 not addressed |

   These were the top rows.

   | P(recovery) | Speed (P) | Paper | Page | Passage content |
   |---|---|---|---|---|
   | 0.97 | slow (0.89) | Baco et al., *Amid fields of rubble…* | 3 | Compares 30 to 40 years since trawling ended with shorter studies of 5 to 10 years |
   | 0.97 | slow (0.88) | same | 2 | Reports signs of recovery on the recovering seamounts and in patches on those still trawled |
   | 0.97 | slow (0.78) | same | 2 | Describes the replicate AUV image transects on still-trawled and recovering seamounts |
   | 0.97 | slow (0.73) | *On a trawled north Pacific seamount…* | 2 | Reports recovery on Emperor seamounts left untrawled for about 40 years |

   The passage text is publisher copyright, so this public copy paraphrases it; the app quotes it.

4. **Reading the evidence.** It called `read_rows` twice to fetch the full text of the top
   `passage_id`s for quoting.
5. **Cross-check against the preset answers.** It read `coded`, ranking passages by the preset
   `strength` score so that replicated surveys come before anecdotes:

   ```sql
   SELECT passage_id, title, page, folder, strength, direction, evidence_type, pressure, crit_r_recovery
   FROM coded WHERE content > 0.5 AND crit_r_recovery > 0.7 AND lower(text) LIKE '%trawl%'
   ORDER BY strength DESC LIMIT 25
   ```

6. **Second `decide`.** It restricted the search to the four key papers by title, with broader
   words ("closure", "ceased", "stopped"), to catch passages the first filter missed.
7. **Counter-evidence.** It read the `coded` passages where `pressure = 'bottom_trawling'` and
   `direction = 'weakens'`, to find passages that say the opposite.

The agent then wrote its answer from the quoted passages, citing title and page.

## Citations

Each row carries `title`, `page`, `passage_id`, `doc_id` and `file`, so the agent can cite
"Baco et al., *Amid fields of rubble…*, p. 2". It cannot yet give a full reference.

- **No bibliographic table.** There are no authors, year, journal or DOI until the planned
  metadata stage looks each paper up in Crossref and OpenAlex.
- **PDF pages.** The page is the PDF page number, not the journal page.
- **Unchecked quotes.** Nothing checks that text the agent presents as a quote appears in the
  passage. The planned `check_quotes` tool will do this. Until then a paraphrase can appear as
  a quote.

## Export

geo-agent's session report treats a tool argument named `sql` as a query, so `read_rows` and
`decide` calls should appear as SQL chunks, and the report's appendix keeps every call's full
arguments, including `decide`'s questions. The exported code will not re-run, for three
reasons: `passages` and `coded` are views that exist only inside the server, the bucket is
private, and the export assumes anonymous reads from the public NRP endpoint. `decide`'s Jev
step is not SQL at all. The export has not been tested on the private app. Making it
reproducible would need geo-agent to handle tools other than SQL, or the server to return code
that re-runs.

## Expert verification

An expert with the PDFs and no software would treat this as a small systematic review.

1. **Define the question and inclusion rules.** Seamount bottom fauna after trawling ended, with
   observed recovery or lack of it. Decide whether evidence from other regions counts.
2. **Screen the corpus.** Go through titles and abstracts across all folders, especially 8.2.3
   Megafauna, 8.2.4 Corals and Sponges, and 8.5 Ecosystem function, and pick the candidate
   papers.
3. **Read each candidate in full** and mark every passage that bears on the question, positive
   or negative.
4. **Extract each passage into a sheet** with the paper and page, the seamount and whether it is
   in the Emperor chain, the years since trawling stopped, the taxa, the study design (replicated
   transects or single dives), the finding, and whether it supports or weakens the case for
   recovery.
5. **Appraise and synthesise.** For example: recovery is visible after 30 to 40 years but slow
   and patchy, based mainly on Baco et al.'s AUV transects on the Hancock seamounts.

To check the tool's output specifically, the expert would do three things.

- **Precision.** For each passage the agent quotes, open the PDF at that page and confirm that
  it says what is claimed and is about the right place.
- **Recall.** This is the weak point. The agent's keyword filter decides what Jev ever sees, so
  a passage saying "after fishing ceased, colonies regrew" without the word "trawl" can be
  missed. The expert lists every passage that should have been found in the key papers and
  checks whether each is among the 58 positives. Missing passages show whether the filter or
  Jev is at fault.
- **A blind sample.** Label about 100 passages, including negatives, without seeing Jev's
  answers, ideally with two people, and then compare. This gives a real precision and recall
  at 0.5 and 0.7.

## Known weaknesses

- **Duplicate paragraphs.** The same paragraph can appear twice when one paper is in the corpus
  as two slightly different PDFs. Near-duplicate detection would fix this.
- **Fragmented answers.** Jev answers per paragraph and never sees the whole paper, so the
  synthesis is left to the chat agent and the reader.
- **Unchecked codes.** No person has checked the preset answers or the custom ones yet.
- **No log of the questions.** The server records `decide`'s SQL but not the question text.
  Adding the questions to the log is a small change, and it would let a reader audit exactly
  what the agent asked.
- **Unverified quotes and short citations,** as described under Citations.
- **Export does not re-run,** as described under Export.
