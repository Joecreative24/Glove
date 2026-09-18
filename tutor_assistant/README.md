# Tutor assistant

A local assistant that turns 30 seconds of post-session notes into finished output.

```
notes in -> classify (student, topics, weak spots, promises)
         -> store in SQLite (student memory)
         -> feedback draft + materials pick (Claude)
         -> outbox, waiting for your approval
         -> clipboard / file / Gmail draft
```

Four pieces, all driven from one `tutor` command:

| Piece | What it does |
|---|---|
| **Post-session feedback** | Dump three messy bullets. Get a warm, personalised message in your voice, matched to the student's level and board, ready to paste into GoChat. |
| **Materials dispatch** | Tag your HTML/Word resources by board + topic (local folder or Google Drive). After a session the assistant picks the right ones, gets share links, and drafts the message. |
| **Student memory** | SQLite: student, board, level, topics covered (with counts), recurring weak spots, what you promised to send next. This is what makes feedback feel personal months later. |
| **Schedule mirroring** | GoStudent slots -> local table -> Google Calendar (ICS import or API push) with prep reminders and buffers, plus a nightly brief: "tomorrow you have X, Y, Z, here's what you covered last time". |

## Install

```bash
cd tutor_assistant
pip install -e .            # core: anthropic + pydantic
pip install -e ".[google]"  # optional: Drive share links, Gmail drafts, Calendar push
pip install -e ".[dev]"     # pytest
```

Credentials: either `export ANTHROPIC_API_KEY=...` or run `ant auth login` once. Copy `.env.example` if you
want to pin the database path, model or timezone.

The model defaults to `claude-opus-5`. Every call enables Anthropic's server-side refusal fallback, so a
rare policy decline is re-run on a fallback model inside the same request instead of failing the pipeline.

## Two-minute walkthrough

```bash
tutor init
tutor voice set "Friendly, brisk, first names, specific praise before next steps. British English."

tutor student add "Dapo" --board AQA --level "GCSE Higher" --subject English --parent "Mrs Adeyemi"

# tag resources with the filename convention  BOARD - topic one, topic two - Title.ext
tutor materials index ~/Tutoring/Resources
tutor materials list

# after the lesson: the whole loop in one line
tutor log "Dapo — past perfect, still confuses since/for, did well on the reading comp, send tense worksheet"

tutor queue list
tutor queue show 1            # read the feedback draft
tutor queue edit 1            # tweak it in $EDITOR if you like
tutor queue send 1            # copies to clipboard -> paste into GoChat
tutor queue send 2 --via gmail --to parent@example.com   # materials message as a Gmail draft
```

Sending a materials message marks that session's promises as fulfilled, so the next feedback draft
stops saying "I'll send that over".

## Student memory

```bash
tutor student show dapo
```

prints topics covered with counts, weak spots ranked by how often they recur, open promises and the last
five session summaries. Everything Claude drafts is built from this history, so a message in March can
say "since/for has finally clicked" because the database knows it was flagged four times in January.

Mark a weak spot fixed with `tutor student resolve <weak_spot_id>`.

## Materials

**Local folder.** Name files `AQA - past perfect, since vs for - Tense worksheet.html` and run
`tutor materials index FOLDER`. Files that do not follow the convention can be tagged in a `tags.json`
sidecar in the same folder:

```json
{"untagged.html": {"board": "AQA", "topics": ["fronted adverbials"], "title": "Adverbials"}}
```

or afterwards with `tutor materials tag <id> --board AQA --topics "past perfect, since vs for"`.
Share links for local files are `file://` URIs; swap the folder for Drive when you want real links.

**Google Drive.** `tutor materials sync-drive <folder-id>` indexes a Drive folder (recursively) using the
same name convention, or `appProperties` `board` / `topics` if you set them. Share links are created only
when a material is actually chosen for a message ("anyone with the link can view").

Before asking Claude, the pipeline pre-filters materials by board and topic-word overlap, so the model only
ever sees a short candidate list and picks at most three.

## Schedule and the nightly brief

```bash
tutor schedule add Dapo 2026-09-19T16:00 --minutes 60     # manual
tutor schedule import gostudent.ics                        # or import an ICS export
tutor schedule list --days 7

tutor schedule export week.ics --prep 30 --buffer 15       # -> Google Calendar > Settings > Import
tutor schedule push --days 14                              # or push via the Calendar API (google extra)

tutor brief                        # tomorrow, written by Claude
tutor brief --raw                  # the plain dossier, no API call
tutor brief --date 2026-09-22 --file ~/briefs.txt
```

Exported events carry a prep alarm, optional buffer blocks before and after, and a description with the
last session summary, top weak spots and anything still to send. Imported slots are matched to students by
name in the event title; unmatched ones are listed so you can fix them.

For a genuinely nightly brief, schedule it:

```
# crontab -e   (21:00 every evening)
0 21 * * * /usr/bin/env ANTHROPIC_API_KEY=... tutor brief --file ~/briefs.txt
```

## Offline mode and tests

`--fake` swaps Claude for a small rule-based stand-in so every command runs without network access. The
test suite uses the same stand-in:

```bash
python -m pytest
```

## Layout

```
tutor_assistant/
  cli.py              the `tutor` command
  pipeline.py         notes -> classify -> store -> drafts -> outbox
  llm.py              Claude calls (structured outputs) + FakeLLM
  db.py               SQLite schema and repository
  models.py           Pydantic models for records and Claude outputs
  materials.py        local/Drive index, candidate pre-filter
  schedule.py         ICS parse/export, nightly brief
  google_services.py  optional Drive / Gmail / Calendar plumbing
  senders.py          clipboard and file output
tests/                offline tests (pytest)
```

## Not building code?

The same wiring runs in n8n or Make: a webhook or form for the notes, an HTTP node calling the Claude
Messages API with the prompts from `llm.py`, a Google Sheet or SQLite node for memory, Drive and Gmail
nodes for dispatch. The prompts and the data model here are the part worth keeping.
