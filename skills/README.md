# Skills

`grilling` and `grill-me` come from [mattpocock/skills](https://github.com/mattpocock/skills) by Matt Pocock, under the MIT licence kept in [`LICENSE`](LICENSE) in this folder. [`UPSTREAM`](UPSTREAM) records the upstream commit the copies were taken from.

- `grilling`: the interview itself. Asks about a plan until every decision is settled, with a recommended answer for each question.
- `grill-me`: a manual trigger (`/grill-me`) that starts `grilling`.

## Local changes

The copies here are upstream's files plus a small overlay, kept apart in [`overlays/grilling/`](overlays/grilling/) so the change is easy to see and to drop:

- `description-suffix.txt` adds one sentence to the skill's description: use the skill proactively when confidence in the requirements is only medium or low. Upstream fires it only when asked.
- `append.md` adds a closing section: ask one question per message instead of a whole round. Upstream asks every open question at once; these working agreements ask one at a time.

## Updating

Upstream is tracked, not frozen. To take its latest version:

```bash
./scripts/sync-skills.sh            # fetch upstream main, re-apply the overlay
git diff skills/                    # read what changed upstream
./tests/run.sh                      # the overlay must still apply cleanly
git commit -m "chore(skills): sync grill skills with upstream" -- skills/
./scripts/install-skills.sh         # copy to ~/.claude/skills
```

`--ref <tag or commit>` fetches a particular upstream version. If upstream changes in a way the overlay no longer fits (say, it adopts the proactive wording itself), edit or delete the overlay file rather than the synced copy.
