# Research: traceability for AI-built software

Date: 2026-11-16 · Depth: deep (1 of 3)
Volatility: slow
Question: Which way of linking requirements to tests best helps verify software written by AI coding agents for a solo developer: a light convention, medium traceability tooling, or heavy executable specifications?
Feeds: feature-item IDs and test links (to be decided)

## Answer

Every option checks the same thing: that each item has a linked test, that no test names an unknown item and, with some tools, that no link outlived a requirement change. None checks that the linked test actually exercises the item; a wrong but valid ID passes them all. Among the tools, OpenFastTrace (OFT) is the best fit for all three stacks. It reads tags from `.ts`, `.py` and `.rs` files, voids old links when an item's revision is bumped, and since September 2026 ships agent skills, but it needs Java 17. BDD adds a failure mode the light option lacks: a step definition that raises no error passes, so an empty step makes its scenario pass. The evidence on BDD's benefits is thin. Inference: the light convention, with framework tags where they can be checked strictly and an OFT-style revision rule, gives most of the value. OFT is the medium option worth learning for an industry career.

## Findings

1. OFT 4.11.0 (2026-10-18) is the latest release; 4.x needs a Java 17 runtime. [HIGH] https://github.com/itsallcode/openfasttrace/releases, https://github.com/itsallcode/openfasttrace (README, fetched 2026-11-16)
2. OFT items have IDs `type~name~revision`. Code and tests cover them with comment tags such as `// [utest->dsn~validate-request~1]`. The tag importer lists TypeScript, Python and Rust, and Gherkin scenarios can be items. [HIGH] https://github.com/itsallcode/openfasttrace/blob/main/doc/user_guide/reference/input_format_support.md (main, 2026-11-16)
3. Bumping an OFT revision "voids all existing links" to the item. Reports mark missing coverage (`-impl`), coverage nobody asked for (`+itest`), duplicates and transitive defects. [HIGH] https://github.com/itsallcode/openfasttrace/blob/main/doc/user_guide/introduction/concepts_and_terms.md, …/reference/console_tracing_report.md
4. OFT ships agent skills: `openfasttrace`, with an "LLM Interaction Guidelines" section, and a spec-driven-development skill. The latest commit to them is dated 2026-09-27. [HIGH] https://github.com/itsallcode/openfasttrace/tree/main/.agents/skills
5. Doorstop 3.2 (2026-07-10) stores each item as YAML. A link carries the parent's fingerprint, so a changed parent is flagged. `references` point to whole files, not to test functions. [HIGH] https://github.com/doorstop-dev/doorstop/blob/develop/docs/reference/item.md
6. Sphinx-needs v9.2.0 (2026-11-04) is now a monorepo that includes code links and test-report import. Eclipse S-CORE, an open-source automotive project, links tests to requirements with `FullyVerifies` and `PartiallyVerifies` properties in JUnit XML. [HIGH] https://github.com/useblocks/sphinx-needs, https://github.com/eclipse-score/tooling/tree/main/python_basics/score_pytest
7. BMW's LOBSTER (1.1.0, 2026-11-16) targets ISO 26262 evidence. It reads Python, C++ and GoogleTest; Rust code (not tests) only through a third-party tool, and TypeScript not at all. NVIDIA's SPARK process generates its ISO 26262 tracing chapter from TRLC files. [HIGH] https://github.com/bmw-software-engineering/lobster, https://nvidia.github.io/spark-process/process/tracing/iso_26262/iso26262.html
8. Vitest has had tags since 4.1.0 (current release v5.1.0, 2026-11-02). Tags must be declared in the config, and a test using an undeclared tag throws unless `strictTags` is turned off. [HIGH] https://vitest.dev/guide/test-tags
9. Playwright (v1.65.1) supports tags (`{ tag: '@x' }`) and typed annotations, and the HTML report shows them. The page has no check for declared tags. [HIGH] https://playwright.dev/docs/test-annotations
10. pytest (9.2.0) fails on unregistered marker names under `--strict-markers`. It checks names only, so the value in `@pytest.mark.req("F3-2")` is not checked (inference from the page). [HIGH] https://docs.pytest.org/en/stable/how-to/mark.html
11. In Cucumber, a step whose definition raises no error is marked successful, and returning `null` or `false` does not fail it. [HIGH] https://cucumber.io/docs/cucumber/api/
12. Missing step definitions: playwright-bdd 9.2.1 defaults to `missingSteps: 'fail-on-gen'` but also allows `skip-scenario`. pytest-bdd 9.0.1 raises `StepDefinitionNotFoundError`. cucumber-rs 0.23.0 fails the run only with `fail_on_skipped()`. [HIGH] https://github.com/vitalets/playwright-bdd/blob/main/src/config/types.ts, https://github.com/pytest-dev/pytest-bdd (`exceptions.py`), https://github.com/cucumber-rs/cucumber/blob/main/book/src/writing/tags.md
13. Concordion's latest release is 4.0.1 (2023-07-16); FitNesse's is v20251025. [HIGH] GitHub releases API
14. EARS has six patterns: ubiquitous, WHILE, WHEN, WHERE, IF-THEN and complex. [HIGH] https://alistairmavin.com/ears/
15. Kiro writes acceptance criteria as "WHEN … THE SYSTEM SHALL …" (page dated 2026-09-25). It derives property tests from EARS requirements, links them back in the UI, and lets a failure be fixed in the code, the test or the requirement (2026-08-04). [HIGH] https://kiro.dev/docs/specs/feature-specs/requirements-first/, https://kiro.dev/docs/specs/correctness/
16. Spec Kit numbers requirements `FR-001` and criteria `SC-001`, but its tasks reference user stories (`US1`), not FR IDs. Tests are "OPTIONAL"; when included, they must be written first and fail. There is no test-to-requirement link. [HIGH] https://github.com/github/spec-kit/blob/main/templates/spec-template.md, …/tasks-template.md
17. Böckeler found that agents do not always follow the specs and that reviewing the Markdown is a burden. A bug fix in Kiro grew into 4 user stories and 16 acceptance criteria. [MEDIUM] https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html (2025-10-15)
18. Across 24 open-source projects, more complete traceability went with lower defect rates for three of four activities. This is a single study. [MEDIUM] https://doi.org/10.1109/TSE.2016.2622264 (2017; abstract via OpenAlex)
19. A survey found that BDD specifications suffer the same maintenance problems as automated test suites in general. A 2023 mapping study covered 166 BDD papers. [MEDIUM] https://doi.org/10.1109/SANER.2018.8330207 (abstract), https://arxiv.org/abs/2305.05567
20. LLM-generated Gherkin varies from run to run across models and prompts. [MEDIUM, from the search summary only] https://sol.sbc.org.br/index.php/sbes/article/view/36996 (SBES 2025)
21. Regulated industries. DO-178C requires bidirectional traces between requirements, code and tests, scaled by software level ([MEDIUM] https://en.wikipedia.org/wiki/DO-178C; [LOW] airworthinesscert.com P10.STM checklist, Table A-6). IEC 62304 requires traceability from requirements to tests (clause 5.7.4 per [LOW] https://sii.pl/blog/en/the-importance-of-traceability-from-the-perspective-of-designing-a-medical-device-software/; [LOW] https://jamb.readthedocs.io/en/latest/iec-62304/traceability.html). ISO 26262: only a vendor source, which sells test tools, says it requires bidirectional traceability between requirements and tests ([LOW] parasoft.com).
22. A practitioner guide proposes requirement tokens in test names, checked in CI for untested and orphan IDs. It warns that agents claim coverage for tests that only touch the code path superficially. The author sells no traceability product. [LOW] https://glukhov.org/app-architecture/testing-architecture/specs-tests-code-traceability-ai-development/

## Options

**Light: an ID in the test name plus a grep checker.** It links the test to the item, and the feature table's Test column already links the item to the test. It can check for items without tests, unknown IDs, duplicates, and Test-column entries that disagree with the test names. It works the same in all three stacks, though a Rust function name cannot contain `-` (memory), so `[F3-2]` needs a mapping such as `f3_2`. Agents write it easily.
AI failure modes:
- A real but wrong ID passes.
- An agent can rename a test to silence the checker.
- Renumbering items breaks links silently unless IDs are never reused.
- A changed Expected outcome leaves old tests "linked". OFT's revision bump answers this, and a checker can copy it (inference).

**Framework tags or annotations.** These are the same links in structured form, and reports group them. Vitest's `strictTags` turns an unknown ID into a run-time error if the item IDs are generated into the config (inference). pytest and Playwright check no values, and Rust's test harness has no tags (memory). So the grep checker is still needed for two of the three stacks. Tags are worth adding to the light option, not a replacement for it.

**Tracing tools.**
- OFT: covers all three stacks, Markdown spec items and Gherkin. It uses revisions to invalidate links and is actively released with agent skills. The cost is a Java 17 dependency and a second ID syntax next to the feature table. Agent failure modes: copying a tag onto an unrelated test, or not bumping a revision.
- Doorstop: links item to item; test links are file-level only.
- Sphinx-needs: heavy, needing a Sphinx documentation build. It is used in automotive open-source work, and its full and partial verification markers are a good idea.
- LOBSTER: has no TypeScript support, so it does not fit here.

**BDD and executable specifications.** These link a scenario to its step code, so the specification is the test. Missing steps are caught (by default only in playwright-bdd and pytest-bdd). No-op and weakened steps are not caught (finding 11). In this workflow the lock would have to cover the step definitions as well as the feature files: a shared step weakened later passes every scenario that uses it (inference). BDD adds a translation layer and a maintenance load like a test suite's, with thin evidence of benefit. Concordion is stale. Its real benefit is a readable spec, and the Expected-outcome column already gives that.

**Structured notations (EARS, Spec Kit).** These shape how a requirement is written, not how it links to tests. EARS could replace the free text in the Expected outcome column. Neither Kiro's documentation nor Spec Kit's templates describe a checkable link from tests to requirement IDs.

## Not found

- How the light convention, OFT and BDD compare in practice, or how often AI agents mislink tests.
- The text of the standards: ISO 26262 and IEC 62304 claims rest on secondary or vendor sources. The ASPICE SWE.4 page returned 404.
- Whether a failed OFT trace exits non-zero: the documentation lists 0, 1 ("OFT error") and 2.
- The full SANER 2018 and SBES 2025 papers, and the `spec-kit-trace` extension (not verified).
- Whether Playwright can reject undeclared tags.

## Questions for the owner

1. Should item IDs be short and positional (`F3-2`) or semantic and versioned (`req~export.csv~1`, the OFT style)? Recommended: `F3-2`, with a revision bump when the Expected outcome changes.
2. For the career goal, is it worth taking on Java 17 and learning OFT in one showcase project now, or later?
3. Should tests mark full versus partial verification of an item, as S-CORE does?

## Spot-checked by the coordinator

- OpenFastTrace's tag importer lists Python, Rust and TypeScript (finding 2): held. Checked against the OpenFastTrace repository's `doc/user_guide/reference/input_format_support.md`.
