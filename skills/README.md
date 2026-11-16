# Skills

Two kinds of skill live here: the grill skills, tracked from upstream, and this repository's own skills for the coordinating session.

## Local skills

`coordinating`, `researching` and `verifying-features` are this repository's own, under its MIT licence. They hold the procedure only the coordinator needs (the session talking with the owner), which would be noise in every subagent if it stayed in the always-loaded rules. `rules/working-agreements.md` keeps a one-line trigger for each.

- `coordinating`: delegation and briefs, models and escalation, two strikes, checking reports, reviews and hardening, decision records, escapes and metrics.
- `researching`: when to research, at which depth and on which model, where reports live and when an old one is stale.
- `verifying-features`: the feature pipeline, from feature items before any code to the owner's walkthrough.

A skill's name and description stay loaded until it is used, and its full text loads when it is. Whether general-purpose subagents can use skills was not verified, so nothing a subagent needs lives only in a skill: it is in the rules or in the brief's template.

`scripts/sync-skills.sh` replaces only the upstream skills, so it never touches these, and `scripts/install-skills.sh` installs them with the rest.

## Upstream skills

`grilling` and `grill-me` come from [mattpocock/skills](https://github.com/mattpocock/skills) by Matt Pocock, under the MIT licence kept in [`LICENSE`](LICENSE) in this folder. [`UPSTREAM`](UPSTREAM) records the upstream commit the copies were taken from.

- `grilling`: the interview itself. Asks about a plan until every decision is settled, with a recommended answer for each question.
- `grill-me`: a manual trigger (`/grill-me`) that starts `grilling`.

### Local changes

The copies here are upstream's files plus a small overlay, kept apart in [`overlays/grilling/`](overlays/grilling/) so the change is easy to see and to drop:

- `description-suffix.txt` adds one sentence to the skill's description: use the skill proactively when confidence in the requirements is only medium or low. Upstream fires it only when asked.
- `append.md` adds a closing section. Ask one question per message instead of a whole round: upstream asks every open question at once; these working agreements ask one at a time. Each recommended answer also proposes the decision's binding level, so a "yes" confirms both. Facts in a recommended answer are marked checked or from memory, and a bigger fact becomes background research while the question that depends on it waits.
- `replace.txt` swaps exact text in other files of the skill: here the "a round of questions at a time" description in `agents/openai.yaml` becomes "one question at a time". The sync fails if upstream rewords that text, so the overlay is updated rather than silently skipped.

### Updating

Upstream is tracked, not frozen. To take its latest version:

```bash
./scripts/sync-skills.sh            # fetch upstream main, re-apply the overlay
git diff skills/                    # read what changed upstream
./tests/run.sh                      # the overlay must still apply cleanly
git commit -m "chore(skills): sync grill skills with upstream" -- skills/
./scripts/install-skills.sh         # copy to ~/.claude/skills
```

`--ref <tag or commit>` fetches a particular upstream version. If upstream changes in a way the overlay no longer fits (say, it adopts the proactive wording itself), edit or delete the overlay file rather than the synced copy.

The overlay script adds `append.md` only when its heading is missing, so a changed `append.md` reaches the synced copy through a sync, or by applying the overlay to upstream's file: `scripts/apply-skill-overlay.sh <copy of upstream's skill> skills/overlays/grilling`. The tests check that the synced copy ends with the current `append.md`.
