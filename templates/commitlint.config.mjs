// commitlint config that accepts and rejects the same messages as
// hooks/commit-msg in ai-workflow (https://github.com/Tonttu84/ai-workflow).
// For Node projects that prefer commitlint and husky over that hook.
//
// Copy to the project root as commitlint.config.mjs, install
// @commitlint/cli and @commitlint/config-conventional, and run it from
// husky's commit-msg hook:  npx --no -- commitlint --edit "$1"
//
// Keep `types` and `max` in step with hooks/commit-msg (a test checks it).
// Checked against the hook's test table with @commitlint/cli 21. Known
// differences: commitlint passes an empty message (git aborts those
// anyway), and this file assumes '#' comments and the default
// commit.cleanup, where the hook reads both from git config.

const types = ['feat', 'fix', 'docs', 'test', 'refactor', 'perf', 'build', 'ci', 'chore', 'revert'];
const max = 72;

// The hook's subject shape: type(scope)!: summary, lower-case scope.
const subject = new RegExp(`^(${types.join('|')})(\\([a-z0-9][a-z0-9._/-]*\\))?!?: [^ ]`);

// Subjects the hook lets through unchecked: the ones git writes itself.
const exempt =
  /^(Merge (branch|branches|remote-tracking branch|pull request|tag|commit) |Revert "|Reapply "|(fixup|squash|amend)! )/;

// The message lines as git saves them, read as the hook reads them: up to
// the scissors line, without trailing spaces or leading blank lines, and
// without comment lines only when git's editor template says git drops
// them (with commit -m and -F git keeps them). Assumes '#' comments.
const scissors = '# ------------------------ >8 ------------------------';
const firstLines = (raw) => {
  const all = (raw || '').split(/\r?\n/);
  let strip = false;
  for (const line of all) {
    if (line.startsWith('# Please enter the commit message')) strip = true;
    if (line.startsWith("# with '#' will be kept")) { strip = false; break; }
    if (line.startsWith(scissors)) { strip = true; break; }
  }
  const lines = [];
  for (const line of all) {
    if (line.startsWith(scissors)) break;
    if (strip && line.startsWith('#')) continue;
    const text = line.trimEnd();
    if (lines.length > 0 || text !== '') lines.push(text);
  }
  return lines;
};

export default {
  extends: ['@commitlint/config-conventional'],
  defaultIgnores: false,
  ignores: [(message) => exempt.test(firstLines(message)[0] || '')],
  plugins: [
    {
      rules: {
        'ai-workflow/subject': ({ raw }) => [
          subject.test(firstLines(raw)[0] || ''),
          "the subject must look like 'type(scope)!: summary' with an allowed type",
        ],
        'ai-workflow/blank-second-line': ({ raw }) => {
          const lines = firstLines(raw);
          return [lines.length < 2 || lines[1] === '', 'the second line must be blank'];
        },
      },
    },
  ],
  rules: {
    'ai-workflow/subject': [2, 'always'],
    'ai-workflow/blank-second-line': [2, 'always'],
    'type-enum': [2, 'always', types],
    'header-max-length': [2, 'always', max],
    'header-trim': [0],
    'subject-case': [0],
    'subject-full-stop': [2, 'never', '.'],
    'body-leading-blank': [0],
    'footer-leading-blank': [0],
    'body-max-line-length': [0],
    'footer-max-line-length': [0],
  },
};
