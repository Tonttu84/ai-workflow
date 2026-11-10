# Function limits

Ready config for the function guide in the working agreements: a function does one thing at one level of detail, and a helper earns its place only when its name hides real detail. The numbers below are enforced by the stack's linter, not by eye.

## The starting values

| Measure | Limit |
| --- | --- |
| Cognitive complexity | 15 |
| Cyclomatic complexity (where the tool has no cognitive measure) | 15 |
| Lines per function | about 60 |
| Parameters | 5 |
| Nesting depth | 3 (Clippy and clang-tidy count more levels: see their sections) |

These are a first guess, to revisit once real projects have been measured.

## How to set them

1. **Warnings first.** Turn the checks on as warnings, so the gate stays green while the numbers settle.
2. **Measure.** At kickoff there is little code: keep the starting values. At a migration, run the checks (or Lizard, below) over the existing code and look at how many functions each limit flags. Pick limits that flag only the worst few percent, and record them in `docs/decisions.md`.
3. **Then errors.** Once the flagged functions are fixed or accepted (an inline suppression with a reason), make the checks errors, so the gate enforces them.

Whichever direction a change goes, the review checks it: a function over the limits is split where a piece earns a name; a single-use helper that only passes its arguments on is folded back in.

## ESLint (TypeScript, JavaScript)

Needs `eslint-plugin-sonarjs` for cognitive complexity. In `eslint.config.mjs`:

```js
import sonarjs from 'eslint-plugin-sonarjs';

export default [
  // ...the project's other config
  {
    plugins: { sonarjs },
    rules: {
      'sonarjs/cognitive-complexity': ['warn', 15],
      complexity: ['warn', 15],
      'max-lines-per-function': ['warn', { max: 60, skipBlankLines: true, skipComments: true }],
      'max-params': ['warn', 5],
      'max-depth': ['warn', 3],
    },
  },
];
```

Change `warn` to `error` in step 3. `complexity` is cyclomatic; keep it as a backstop or drop it once the cognitive check is in place.

## Ruff (Python)

Ruff has no warning level: a selected rule fails the check. So in step 1 run the checks as a report that never fails (`--exit-zero`), and add them to `extend-select` in step 3. In `pyproject.toml`:

```toml
[tool.ruff.lint]
# Step 3 only: uncomment to make these checks fail the gate.
# extend-select = ["C901", "PLR0912", "PLR0913", "PLR0915"]

[tool.ruff.lint.mccabe]
max-complexity = 15          # C901, cyclomatic

[tool.ruff.lint.pylint]
max-args = 5                 # PLR0913
max-branches = 12            # PLR0912
max-statements = 50          # PLR0915, Ruff's stand-in for function length
```

```bash
ruff check --select C901,PLR0912,PLR0913,PLR0915 --exit-zero .   # step 1: report only
```

Ruff has no cognitive-complexity or line-count rule. Nesting depth: Ruff's `PLR1702` (too-many-nested-blocks, setting `max-nested-blocks`) was a preview rule when this was written; check `ruff rule PLR1702` before relying on it.

## Clippy (Rust)

In `clippy.toml` at the crate or workspace root:

```toml
cognitive-complexity-threshold = 15
too-many-lines-threshold = 60
too-many-arguments-threshold = 5
excessive-nesting-threshold = 5    # counts impl, trait, mod and the fn body too
```

`excessive_nesting` counts every nested item and block, not just control flow: an `impl`, a trait, an inline `mod` (such as `mod tests`), the function body and each block inside it. `impl X { fn f() { if a { if b {} } } }` is already four deep, so 5 leaves about three levels inside a method, like the nesting depth 3 of the other tools.

The thresholds do nothing unless the lints run. `too_many_lines` is in the pedantic group and `cognitive_complexity` in the restriction group, so neither is on by default; `too_many_arguments` is on by default (complexity group, threshold 7); `excessive_nesting` does nothing until its threshold is set. Clippy's own docs discourage `cognitive_complexity`, as a poor proxy for how hard code is to read: treat its warnings as hints and lean on the length and nesting lints. Group membership moves between Clippy releases: check the lint list for the project's toolchain. Turn the lints on in `Cargo.toml`:

```toml
[lints.clippy]
cognitive_complexity = "warn"
too_many_lines = "warn"
too_many_arguments = "warn"
excessive_nesting = "warn"
```

In a Cargo workspace, put the table in the root `Cargo.toml` as `[workspace.lints.clippy]`, and opt each member crate in with this in its own `Cargo.toml`:

```toml
[lints]
workspace = true
```

In step 3, make the gate run `cargo clippy --all-targets -- -D warnings`, or set the lints to `"deny"`.

## clang-tidy (C++)

In `.clang-tidy`:

```yaml
Checks: 'readability-function-size,readability-function-cognitive-complexity'
WarningsAsErrors: ''   # step 3: the same two check names here
CheckOptions:
  - key: readability-function-size.LineThreshold
    value: 60
  - key: readability-function-size.ParameterThreshold
    value: 5
  - key: readability-function-size.NestingThreshold
    value: 4
  - key: readability-function-cognitive-complexity.Threshold
    value: 15
```

Add the two names to the project's existing `Checks` list rather than replacing it. `NestingThreshold` counts the function body as level 1, so 4 here is the same as ESLint's `max-depth` of 3. `readability-function-cognitive-complexity` defaults to 25; `readability-function-size` flags only functions over 800 statements by default, and its other thresholds are off until set.

## Lizard (any language, for measuring)

[Lizard](https://github.com/terryyin/lizard) reads most languages and is the quick way to do step 2 across a codebase:

```bash
lizard -C 15 -L 60 -a 5 src/        # cyclomatic 15, length 60, 5 parameters
lizard -w -C 15 -L 60 -a 5 src/     # only the functions over a limit
```

The summary at the end counts the functions and those over a limit; the share of flagged functions is the number to bring down to the worst few percent. Lizard measures cyclomatic complexity, not cognitive complexity, and has no nesting limit in these flags.
