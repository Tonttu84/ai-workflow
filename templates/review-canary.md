# Review canary

<!-- Copy to <project>/metrics/review-canary.md in the private repository
     (the one named in the working agreements' credentials bullet), one
     file per project. One row per review run with a planted bug: before
     a review, the coordinator plants one known bug in a copy of the
     change (templates/review-brief.md, D80). -->

Did the cold reviewer catch the bug planted in a copy of the change?

| Date | Change | Planted bug | Caught | Reviewer model and effort |
| --- | --- | --- | --- | --- |
| <YYYY-MM-DD> | <PR #n or a short title of the change> | <what was planted, and where: file:line> | <yes or no> | <opus, xhigh> |

- Caught: `yes` when a finding names the planted bug, `no` otherwise. A finding nearby that misses the bug itself is `no`.
- A review that misses the bug does not count. At most one rerun follows, with a fresh reviewer, as a row of its own; after a second miss the coordinator tells the owner, and the review is not done until the owner decides.
- Reviewer model and effort: as passed to the agent, such as `opus, xhigh` or `opus, normal`.
- When summarising, give counts, not percentages: "4 of 5 caught", not "80%".
