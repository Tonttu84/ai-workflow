# Tracing with OpenFastTrace

<!-- For a project whose AGENTS.md says "Traceability: light and OpenFastTrace".
     The light check, scripts/check-trace-links.sh, runs in every project
     with feature files (check-features.sh runs it unconditionally), so
     test names keep their item tags; a showcase project adds OFT on top,
     the tool the owner chose to learn now (ai-workflow D91). Checked against
     OFT 4.11.0 (2026-10-18) on 2026-11-16. -->

OpenFastTrace (OFT) reads specification items from Markdown and coverage tags from source and test files, then reports every item whose coverage is missing, outdated or unwanted.

## Setup

- Java 17 or newer: "OpenFastTrace requires Java 17 or newer" (Windows: `winget install eclipse.temurin.17.jre`). https://github.com/itsallcode/openfasttrace/blob/4.11.0/doc/user_guide/installation/windows.md
- Pin the jar: download `openfasttrace-4.11.0.jar` from https://github.com/itsallcode/openfasttrace/releases and name the version in `AGENTS.md`; upgrade it as its own change.

## Items: the feature file

The feature table (`templates/feature.md`) stays the source of IDs and revisions. Below it, under `## Trace items`, write one OFT item per row:

```markdown
### F3-2 Download last month as CSV
`feat~f3-2~1`

Needs: itest
```

- The ID is `feat~<id in lower case>~<Rev>`: item `F3-2` at Rev 1 is `feat~f3-2~1`. OFT IDs are `type~name~revision`: the type is ASCII letters, a name fragment starts with a letter and holds letters, digits, `_` and `-`, and the revision is a number. https://github.com/itsallcode/openfasttrace/blob/4.11.0/doc/spec/design.md (`dsn~md.specification-item-id-format~3`)
- The heading right above the ID becomes the item's title; `Needs: itest` asks for coverage by a test.
- A Rev bump changes the table and the OFT ID in the same commit. In OFT, raising the revision "voids all existing links" to the item, so every test tagged with the old revision stops counting until it is rechecked and retagged. https://github.com/itsallcode/openfasttrace/blob/4.11.0/doc/user_guide/introduction/concepts_and_terms.md
- Nothing checks yet that the table's Rev and the OFT revision agree: compare them in review until a check exists.

## Tests: the coverage tag

Each test that covers an item carries a tag in a comment next to it, at the item's current revision:

```ts
// [itest->feat~f3-2~1]
test('downloads last month as CSV', async ({ page }) => { /* ... */ });
```

- Python: `# [itest->feat~f3-2~1]`; Rust: `// [itest->feat~f3-2~1]`.
- OFT's tag importer reads `.ts`, `.js`, `.cjs`, `.mjs`, `.py` and `.rs` files, but not `.tsx`: keep tagged tests in `.ts` files. https://github.com/itsallcode/openfasttrace/blob/4.11.0/doc/user_guide/reference/input_format_support.md

## The gate

```sh
java -jar <path>/openfasttrace-4.11.0.jar trace docs/features <test directories>
```

- It prints a report of the defects (`-v failure_details` is the default); `-v minimal` prints only `ok` or `not ok`. https://github.com/itsallcode/openfasttrace/blob/4.11.0/doc/man/man_1.md
- Exit status: 0 no defect; 1 a defect or an OFT error; 2 a command-line error. The user guide lists 1 only as "OFT error"; the source shows a defect returns 1 too (`TraceCommand.run()` returns `trace.hasNoDefects()`, which `CliStarter` maps to `FAILURE(1)`; design item `dsn~cli.tracing.exit-status~1`; test `CliExitIT.testCliExitCode_Failure`, all at tag 4.11.0).
- Before relying on it, prove it once in the project, and again after each OFT upgrade: three deliberately broken links must each make the trace exit 1. Retag one test to an old revision; tag one with an unknown ID (`feat~f99-1~1`); remove the only tag of one item. Put each back after. Whether OFT counts a tag that names an unknown item as a defect was not checked in the docs; this run settles it.
