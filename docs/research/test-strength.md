# Research: measuring whether AI-written tests actually test

Date: 2026-11-16 · Depth: deep (2 of 3)
Volatility: slow
Question: How can a workflow measure whether tests written by AI coding agents actually check behaviour, rather than passing whatever the code does, and which tools fit Rust, TypeScript and Python projects?
Feeds: the hardening step's measures and gate checks (to be decided)

## Answer

Coverage cannot answer the question: it shows what code a test reaches, not what it checks, and LLM-written tests tend to assert the code's current behaviour, so they can reach 100% coverage while killing almost no mutants (findings 1–4). Mutation testing is the established measure that does answer it: a surviving mutant is a concrete change that no test noticed, and mutant detection tracks real-fault detection better than coverage does, though only weakly once suite size is controlled (findings 5–6). All three stacks have a maintained tool that can limit a run to changed code: cargo-mutants `--in-diff` (Rust), StrykerJS incremental mode plus `--mutate` line ranges (TypeScript/Vitest), and mutmut 3 (Python, function-level reuse; needs WSL on Windows) (findings 9–13). Inference: the strongest fit for this workflow is diff-scoped mutation testing in the hardening step, with surviving mutants on changed lines reviewed one by one rather than gated by a score, plus cheap lint and changed-line coverage checks in the local gate.

## Findings

1. Coverage shows what code is "reached by a test, and not whether the test really checks anything". [HIGH] https://github.com/sourcefrog/cargo-mutants (README, v27.1.0, read 2026-11-16)
2. Once suite size is controlled, coverage has a low to moderate correlation with suite effectiveness; the authors advise against using it as a quality target. [MEDIUM] https://cs.ubc.ca/~rtholmes/papers/icse_2014_inozemtseva.pdf (ICSE 2014), https://www.cs.ubc.ca/award/2014/06/acm-sigsoft-distinguished-paper-award-icse
3. "LLM-based test generation approaches mainly capture the actual program behavior making bug detection difficult." [MEDIUM] https://arxiv.org/abs/2410.21136 (Konstantinou, Degiovanni, Papadakis; v2 2026-10-05)
4. Some LLM-generated suites "achieve 100% coverage but only 4% mutation score"; feeding surviving mutants back into the prompt raised mutation score above EvoSuite and plain prompting (204 subjects). [MEDIUM] https://arxiv.org/abs/2506.02954 (MutGen, v8 2026-04-15). Second source for findings 3–4: CANDOR calls LLM assertions "regression oracles" that record current behaviour. [MEDIUM] https://arxiv.org/html/2506.02943v2 (2025, search snippet only)
5. About 73% of 357 real Java faults were coupled to standard mutants; mutant detection correlated with real-fault detection more strongly than statement coverage did. [MEDIUM] https://people.cs.umass.edu/~rjust/publ/mutants_real_faults_fse_2014.pdf (FSE 2014, abstract)
6. Controlling for suite size, correlations between mutation score and real-fault detection are weak, but suites chosen for higher mutation scores detect significantly more faults than random suites of the same size. [MEDIUM] https://core.ac.uk/download/154760839.pdf (Papadakis et al., ICSE 2018)
7. Google mutates only changed code during code review, drops "arid" (uninteresting or uncovered) lines, and surfaces individual mutants to authors and reviewers; used by 6,000 engineers in 2018, evaluated with 24,000+ developers in 2021. [MEDIUM] https://research.google/pubs/state-of-mutation-testing-at-google/ (ICSE SEIP 2018), https://arxiv.org/abs/2102.11378 (2021)
8. Meta's ACH uses an LLM to generate few, targeted mutants for a concern (privacy), then tests that kill them; an LLM equivalent-mutant detector reached precision/recall 0.95/0.96 with preprocessing; engineers accepted 73% of tests. [MEDIUM] https://arxiv.org/abs/2501.12862 (FSE 2025 Industry)
9. cargo-mutants `--in-diff FILE` tests only mutants overlapping changed regions; changes to test code alone produce no mutants; "not a substitute for a full test run". [HIGH] https://mutants.rs/in-diff.html (page undated; tool v27.1.0, 2026-06-02 per https://github.com/sourcefrog/cargo-mutants/releases)
10. cargo-mutants' cost is one incremental build plus one test run per viable mutant; the docs set no score target and treat each missed mutant as a signal; equivalent mutants are marked `#[mutants::skip]`; it needs non-flaky tests. [HIGH] https://mutants.rs/using-results.html, https://mutants.rs/performance.html (undated)
11. StrykerJS incremental mode (since 6.2) reuses results for unchanged code and tests; with Vitest it detects changed tests precisely, but not changes outside mutated and test files (dependencies, env, snapshots). [HIGH] https://stryker-mutator.io/docs/stryker-js/incremental/ (undated; StrykerJS v10.1.1, 2026-10-23 per https://github.com/stryker-mutator/stryker-js/releases)
12. StrykerJS `thresholds.break` makes Stryker exit 1 below the given score (default null); `--mutate` accepts `file:start-end` line ranges, but not combined with a glob on the same entry. No git-diff option found in docs or the last three releases. [HIGH] https://stryker-mutator.io/docs/stryker-js/configuration/ (undated)
13. mutmut 3.8.1 (2026-10-28, Python ≥3.10) re-tests only mutants in functions whose source changed, supports `# pragma: no mutate`, and needs fork, so on Windows it must run in WSL. [HIGH] https://pypi.org/project/mutmut/, https://mutmut.readthedocs.io/en/latest/
14. `@vitest/eslint-plugin` recommended rules include `expect-expect` (test with no assertion), `valid-expect`, `no-conditional-expect`, `no-disabled-tests`, `no-focused-tests`. [HIGH] https://github.com/vitest-dev/eslint-plugin-vitest (version not shown)
15. diff-cover 11.0.2 (2026-11-14) gates coverage of changed lines (`--fail-under`, `--compare-branch`) from Cobertura or LCov reports; it measures lines, not branches. [HIGH] https://pypi.org/project/diff-cover/
16. Vitest 5.1 `coverage.thresholds` supports per-metric, per-file and glob thresholds. [HIGH] https://vitest.dev/config/coverage
17. LLM-generated tests consistently show smells such as Assertion Roulette and Magic Number Test. [MEDIUM] https://arxiv.org/abs/2410.10628v2 (v2 Nov 2025)
18. An agent built on Claude Code wrote Hypothesis property tests for 100 Python packages; 56% of its bug reports were valid bugs. [MEDIUM] https://arxiv.org/html/2510.09907v1 (Oct 2025). Hypothesis 6.170.15, 2026-11-06. [HIGH] https://pypi.org/project/hypothesis/
19. ImpossibleBench measures agents passing contradictory tests through shortcuts "from simple test modification to complex operator overloading". [MEDIUM] https://arxiv.org/abs/2510.20270 (2025-10-23). Secondary summaries report Claude models mostly edited tests, and read-only test access cut cheating. [LOW] https://www.lesswrong.com/posts/qJYMbrabcQqCZ7iqm/impossiblebench-measuring-reward-hacking-in-llm-coding-1
20. Thoughtworks Radar moved mutation testing to Adopt (Nov 2026, from Trial in Apr 2026), framing it as a guardrail for AI-generated tests and advising runs on recently changed code. [LOW: editorial; Thoughtworks sells consulting, not a mutation tool] https://www.thoughtworks.com/radar/techniques/mutation-testing

## Options

**A. Diff-scoped mutation testing (detects: missing or weak assertions, tests that mirror code, mocks that hide the unit).**
- Rust: `git diff <base> > d.diff && cargo mutants --in-diff d.diff`. Fits the gate best of the three; the docs describe this exact use locally and in CI.
- TypeScript: StrykerJS with the Vitest runner and `incremental: true`; for a true diff run, a script must turn `git diff` hunks into `--mutate file:start-end` entries (inference: no built-in option found).
- Python: mutmut 3 (incremental by function, WSL only on Windows) or cosmic-ray 8.4.6 (Windows status not confirmed).
- Cost: roughly (mutants on changed lines) × (incremental build + test run) (finding 10); no benchmark found, so measure on a real feature. Pitfalls: equivalent mutants need a recorded skip; flaky tests break the method; test-only changes are invisible; incremental runs miss effects on unchanged code.
- Policy options from the sources: Stryker's `break` score (finding 12); Google's per-mutant review without a score gate (finding 7); cargo-mutants' "treat each miss as a signal" (finding 10). Inference: "no unexplained surviving mutant on changed lines" is the policy closest to the sources and to the owner's preference for pass/fail checks, with each exception a skip annotation that states its reason.

**B. Full mutation runs on a schedule.** Covers what diff runs miss (finding 9). Inference: weekly or before a release, in CI, not the push gate.

**C. Changed-line coverage.** diff-cover over LCov/Cobertura (Python, and Rust/Vitest via LCov: memory that `cargo llvm-cov` and Vitest emit LCov); Vitest thresholds. Cheap and gateable; finds untested code, not weak assertions (findings 1–2).

**D. Test lint rules.** `@vitest/eslint-plugin` recommended set catches assertion-free, disabled and focused tests at near-zero cost. No equivalent Rust or pytest rule was verified. Smell detectors (finding 17) flag style, not whether a test checks behaviour; inference: low value as a gate.

**E. Property-based tests** (proptest, fast-check with `@fast-check/vitest`, Hypothesis). Not a measure but a stronger oracle: properties check what should hold, which counters finding 3. Evidence that agents can write them well: finding 18. Cost: slower, randomised tests; seeds must be pinned or replayed to stay deterministic (memory).

**F. LLM-generated targeted mutants** (ACH, LLMorpheus https://arxiv.org/abs/2404.09952). The hardening agent writes mutants for the feature's own risks and then tests that kill them. Strong evidence at Meta (finding 8); no packaged open tool verified; costs tokens and needs an equivalence check.

**G. Tamper checks** (already in the workflow: locked test files). Finding 19 supports keeping them; mutation testing does not catch a deleted test whose code is also deleted.

## Not found

- Run-time benchmarks for any of the three tools on a small or medium project.
- A git-diff option in StrykerJS or a diff mode in mutmut (only function-level reuse).
- Primary confirmation of cosmic-ray on Windows, of `@fast-check/vitest` and proptest current versions, and of a Rust or pytest "test has no assertion" lint.
- Studies of mutation testing on agent-written tests in ordinary projects; evidence is from Meta, benchmarks and Thoughtworks.
- Long-term effect of Google's mutants on test quality (abstracts silent).
- ImpossibleBench's mitigation numbers in the primary paper; LLMorpheus's survivor breakdown (63% behavioural, 8.5% equivalent) seen only in a vendor summary.
- Any evidence for assertion-density as a quality signal.

## Questions for the owner

1. Should diff-scoped mutation testing run in the local push gate, or only in the hardening step and CI? Recommended: hardening step and CI, because push time grows with each changed function.
2. Gate on "no unexplained survivor on changed lines" rather than a score threshold? Recommended: yes.
3. May the hardening agent add skip annotations itself, if each states a reason the reviewer checks? Recommended: yes.
4. For Python on this Windows machine, is running mutmut in WSL acceptable? Recommended: yes, rather than an unverified tool.
5. Is the token cost of LLM-written targeted mutants (option F) worth trying on one feature? Recommended: yes, as a trial.

## Spot-checked by the coordinator

- cargo-mutants `--in-diff` mutates only the changed regions (finding 9): held. Checked against https://mutants.rs/in-diff.html.
