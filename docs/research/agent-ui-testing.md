# Research: agents exercising a web app's UI as a periodic acceptance check

Date: 2026-11-16 · Depth: deep (3 of 3)
Question: How do teams use AI agents to operate a web app's real UI as a periodic acceptance check, and how do they stop the agent from reporting a pass when the feature does not work?
Feeds: a periodic agent-driven UI run and its pass/fail oracle (to be decided)

## Answer

The studies and the eval guidance agree that an agent's own report should not decide a pass. Hallucinated final answers are a main source of false passes (F2, F8, F10). LLM judges do better, but at the best measured precision (70–82%), 18–30% of the runs they pass are actually failures (F1, F2). An agent's reasoning text can push judges into more false passes (F4). The oracle with the fewest false passes checks the end state after the run: database rows, created objects or the URL, compared against a stated expected outcome. WebArena, Stripe's benchmark and Anthropic's guidance all grade this way (F7, F8, F10). Its known weakness is rejecting valid alternative paths, which produces false alarms, not false passes (F1). Agent runs cost $0.6–30 per task or flow and take minutes each (F11, F12). Slack places them on top of deterministic CI tests, not in their place (F11). *Inference:* pass a feature item only when a deterministic check of its "Expected outcome" passes. Let everything else (judge, screenshots, step log) downgrade a pass to fail or unknown, never upgrade one.

## Findings

Oracle reliability
1. AgentRewardBench scored 1,302 web-agent trajectories against expert labels. No LLM judge exceeded 70% precision (best 69.8%, recall 83.1%). Benchmark rule-based checks reached 83.8% precision but only 55.9% recall. Judges "easily agree with the agent's reasoning even when it is wrong". [MEDIUM] https://arxiv.org/html/2504.08942v2 (v2, 2025-10-06)
2. WebJudge works from the task's key points, the key screenshots and a binary verdict. It ignores the agent's final answer, because those answers "often contain hallucinations". It reaches 85.7% agreement with humans and 73.7–82.0% precision on AgentRewardBench. The WebVoyager evaluator, which reads final answers, agrees with humans only 73.9–78.7% of the time, with many false positives. [MEDIUM] https://arxiv.org/html/2504.01382v4 (v4, Oct 2025)
3. Agents reported near 90% on WebVoyager reach 30–61% on Online-Mind2Web under human evaluation. Same source as F2.
4. Rewriting only an agent's reasoning, with the same actions and screenshots, raised judges' false-positive rate by about 20–30 points. Prompting judges to rely on evidence helped only partly. Hiding the reasoning removes the attack but costs up to 13 points of recall. [MEDIUM] https://arxiv.org/html/2601.14691v2 (v2, 2026-01-22)
5. browser-use runs a gemini-2.5-flash judge after the agent says `done`. The judge returns a JSON verdict and aligns 87% with 200 hand-labelled traces; the error direction is not stated. The team repeats tasks to handle variance. [LOW, sells a browser-agent product] https://browser-use.com/posts/our-browser-agent-evaluation-system (2026-02-23)
6. In one study, agents ran natural-language test cases while an LLM judged each assertion from screenshots. They caught 85–94% of failing tests, so 6–15% of real failures were reported as PASS. They failed 43–53% of passing tests. Causes included missing actions, UI the agent could not observe, unverifiable assertions and off-script steps. [MEDIUM, single study, 3 apps] https://arxiv.org/html/2504.01495v1 (v1, 2025-04-02)

State-based oracles
7. WebArena grades tasks that change data with programs run after the agent finishes. They query the database, call the site API or select DOM elements, then check "the result of the execution", which allows many valid paths. [MEDIUM] https://arxiv.org/html/2307.13854v4 (v4, 2024-04-16)
8. Anthropic grades the "outcome", "the final state in the environment": a reservation in the database, not the agent saying "Your flight has been booked". It advises giving judges an "Unknown" option, one isolated judge per criterion, calibration against humans, and pass^k for consistency (0.75³ ≈ 42%). [MEDIUM, model vendor's engineering guidance] https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents (2026-01-09)
9. Loose deterministic checks also pass falsely. WebArena's string matching and unvalidated LLM judge misestimate success by 1.6–5.2 points, for example by accepting "45 + 8 minutes". [MEDIUM; search summary only, not fetched] https://arxiv.org/html/2507.02825v2
10. Stripe graded most tasks with deterministic tests (API calls, UI tests, checks on the Stripe objects created). One agent read an HTTP 400 as proof that "the endpoint is working". [LOW, company blog with benchmark data] https://stripe.com/blog/can-ai-agents-build-real-stripe-integrations (2026-03-02)

Cost, time, flakiness
11. Slack ran Playwright MCP through `claude -p`, 20 runs per configuration, on test workspaces. Failure rates were 0% on a simple flow and about 12% on a medium one. Runs took 5–8 minutes and cost "$15–30 per execution", without token tuning. Generated Playwright tests failed in 8% and 48% of runs. Other failures traced to authentication, navigation timing and session instability. Slack recommends agents for exploration and debugging rather "than for high-frequency CI execution". [LOW, engineering blog; Slack sells no testing product] https://slack.engineering/agentic-testing-where-agents-fit-in-the-e2e-testing-stack/ (2026-06-11)
12. HAL's Online-Mind2Web runs over 300 tasks cost $171 at best, about $0.57 per task. Browser-Use with Claude Sonnet 4 cost $1,577, about $5.26 per task. HAL says some costs are overstated by up to 2× (note dated 2026-10-05). [MEDIUM] https://hal.cs.princeton.edu/online_mind2web (fetched 2026-11-16)

Tooling (local, no paid platform)
13. Playwright MCP (`@playwright/mcp` 0.0.85) reads accessibility snapshots, not pixels. It has tracing and video tools, `--save-session`, `--output-dir`, and `--blocked-origins` and `--allowed-origins`, though it is "not a security boundary". `--caps=testing` adds `browser_verify_*` tools. [HIGH] https://github.com/microsoft/playwright-mcp (fetched 2026-11-16)
14. Playwright 1.56 added test agents. A planner writes `specs/*.md`, a generator writes the tests, and a healer reruns failing tests "until it passes or until guardrails stop the loop", or skips a test it believes is broken. Release 1.59 added `page.screencast` "agentic video receipts", and 1.62 bundled `npx playwright mcp`. The latest release is 1.65. [HIGH] https://playwright.dev/docs/test-agents, https://playwright.dev/docs/release-notes (fetched 2026-11-16)
15. `page.route` with `route.fulfill` mocks requests. `routeFromHAR` records traffic, then replays it with strict URL and method matching. `recordHar` captures all traffic. [HIGH] https://playwright.dev/docs/mock (1.65 docs, fetched 2026-11-16)
16. `claude -p --bare --mcp-config` runs Claude Code headless and reproducibly. `--output-format json` reports `total_cost_usd`, `--json-schema` returns `structured_output`, `--max-budget-usd` caps spend, and `--permission-prompts none` (v2.1.259+) suits unattended runs. [HIGH] https://code.claude.com/docs/en/headless (fetched 2026-11-16)

Commercial tools
17. Momentic sells AI assertions. `assert` sends the DOM, accessibility tree and screenshot to a model, and `assertVisually` sends only a screenshot. They sit next to deterministic `checkElement*` steps. [LOW, vendor docs] https://momentic.ai/docs/reference/commands.md (undated)
18. QA Wolf sells agent-maintained deterministic Playwright code. It warns that runtime-adaptive agents "may 'pass' even when the user experience is broken", and that mocked replays "don't validate the actual backend or side effects". [LOW, vendor] https://www.qawolf.com/blog/blog-making-sense-of-all-the-ai-powered-qa-tools (2026-03-12). Octomind, also a vendor, says AI at runtime causes "false positives or negatives" and should only author and maintain tests. [LOW] https://dev.to/daniel-octomind/ai-doesnt-belong-in-test-runtime-4haa (2025-03-10)

## Options

| Oracle | False-pass risk | False alarms | Cost | Fit here |
|---|---|---|---|---|
| A. Agent's own report | Highest (F2, F3, F10) | Low | None | Evidence only |
| B. LLM judge on screenshots or trajectory | 18–30% of passes wrong (F1, F2); can be manipulated (F4) | Moderate | One call per item | Veto only: hide the agent's reasoning and claim, allow "unknown" (F4, F8) |
| C. Exact check of the item's Expected outcome on seeded data (DB row, file, object) | Lowest (*inference*: no measured rate; loose "contains" checks fail, F9) | Higher: valid alternative paths fail (F1) | A small script per item | Matches the feature file. *Inference:* best primary oracle |
| D. HAR or network assertions | A 2xx is not proof of state; a 400 can be misread (F10) | Low–moderate | Free (F15) | Supporting evidence; third-party calls |
| E. Mocked backend recording calls | Misses real side effects (F18) | Low | Free (F15) | Third parties only (payments, email) |
| F. Step log, trace, video | Not an oracle | – | Free (F13, F14) | Triage and human spot checks |
| G. Generated tests plus healer | The healer can loop to green or skip (F14, F18) | Lower | Cheap once made | Already in CI; script an agent run only after human review |

*Inference, a combined rule.* An item passes only when C passes and evidence (F) exists. A judge (B) that sees only screenshots and the expected outcome can downgrade the item to fail or unknown. Missing evidence counts as unknown, and unknown is not a pass. This keeps C's low false-pass rate and accepts false alarms, which the owner tolerates. Third-party flows use E plus D. Requiring 2–3 runs per item to all pass (pass^k, F8) makes false passes rarer.

*Inference, local set-up.* Run `claude -p --bare --mcp-config` with Playwright MCP against the local app on a seeded database. The agent returns a `--json-schema` report: steps, evidence paths and its claim. A separate script runs the C checks and alone writes pass, fail or unknown. `--max-budget-usd` caps spend. Expect about $1–30 and 5–10 minutes per flow (F11, F12).

*Goal-only (discoverability) runs.* No source measures them. UXAgent uses persona agents only as "pilot-stage" helpers, not as a replacement for human participants (https://arxiv.org/pdf/2504.09407, MEDIUM, abstract only). *Inference:* report goal-only failures as a usability signal, separate from the verdict, because they mix "broken" with "not found".

## Not found

- A measured false-pass rate for a purpose-built post-run database check. F1's 83.8% is for benchmark checks, some of them loose (F9).
- A primary source on scheduling (pre-release, nightly, weekly). Only unfetched vendor-blog search snippets (testdino.com, agentpedia.codes) mention nightly exploratory jobs.
- A study of goal-only prompts as a discoverability test.
- Triage practice beyond F6's and F11's failure causes.
- Octomind's site did not resolve, so its DEV mirror was used. F9 and Barr et al.'s oracle survey (https://discovery-pp.ucl.ac.uk/id/eprint/1471263, IEEE TSE 2015) were seen only in search results.
- Playwright MCP's licence and its token use on a small app.

## Questions for the owner

1. Should "unknown" (no evidence, or the judge and the state check disagree) count as a failure? Recommended: yes.
2. What spend is acceptable per run or per month, at roughly $1–30 per flow?
3. Which cadence: before each release, or weekly?
4. May third-party services be hit in their test modes, or always be mocked (option E)?
5. Should goal-only runs be a separate report rather than part of pass/fail? Recommended: yes.
