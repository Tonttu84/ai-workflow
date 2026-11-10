// commitlint config that accepts and rejects the same messages as
// hooks/commit-msg in ai-workflow (https://github.com/Tonttu84/ai-workflow).
// For Node projects that prefer commitlint and husky over that hook.
//
// Copy to the project root as commitlint.config.mjs, install
// @commitlint/cli and @commitlint/config-conventional, and run it from
// husky's commit-msg hook:  npx --no -- commitlint --edit "$1"
//
// Keep `types` and `max` in step with hooks/commit-msg (a test checks it).
// tests/commitlint.test.sh compares the two over the hook's test table
// when COMMITLINT_DIR names an installed commitlint; CI does not run it.
// Like the hook, this counts the subject in characters (code points);
// commitlint's own header-max-length counts UTF-16 units, so it is off.
// Known difference: commitlint passes a message that is empty once
// comment lines are dropped (git aborts an empty message anyway).

import { execFileSync } from 'node:child_process';

const types = ['feat', 'fix', 'docs', 'test', 'refactor', 'perf', 'build', 'ci', 'chore', 'revert'];
const max = 72;

// The hook's subject shape: type(scope)!: summary, lower-case scope.
const subject = new RegExp(`^(${types.join('|')})(\\([a-z0-9][a-z0-9._/-]*\\))?!?: [^ ]`);

// Dependabot's subjects, which the hook lets run past the length limit.
const dependabot = /^(chore|ci)(\([a-z0-9][a-z0-9._/-]*\))?: bump (the [^ ]+ group|[^ ]+ from [^ ]+ to [^ ]+)/;

// Subjects the hook lets through unchecked: the ones git writes itself.
const exempt =
  /^(Merge (branch|branches|remote-tracking branch|pull request|tag|commit) |Revert "|Reapply "|(fixup|squash|amend)! )/;

const gitConfig = (key) => {
  try {
    return execFileSync('git', ['config', '--get', key], { encoding: 'utf8', timeout: 5000 }).trim();
  } catch {
    return '';
  }
};

// The message lines as git saves them, read as the hook reads them. Git
// exports GIT_EDITOR=: when no editor ran (-m, -F): comment lines and the
// scissors line then stay, unless commit.cleanup is strip. After the
// editor, git's template text decides, else commit.cleanup.
const firstLines = (raw) => {
  const configured = gitConfig('core.commentChar');
  const c = configured.length === 1 ? configured : '#';
  const cleanup = gitConfig('commit.cleanup');
  const scissors = `${c} ------------------------ >8 ------------------------`;
  const all = (raw || '').split(/\r?\n/);
  let strip;
  let cut;
  if (process.env.GIT_EDITOR === ':') {
    cut = false;
    strip = cleanup === 'strip';
  } else {
    cut = true;
    strip = !['whitespace', 'scissors', 'verbatim'].includes(cleanup);
    for (const line of all) {
      if (line.startsWith(`${c} Please enter the commit message`)) strip = true;
      else if (line.startsWith(`${c} with '${c}' will be kept`)) {
        strip = false;
        break;
      } else if (line.startsWith(scissors)) break;
    }
  }
  const lines = [];
  for (const line of all) {
    if (cut && line.startsWith(scissors)) break;
    if (strip && line.startsWith(c)) continue;
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
        'ai-workflow/subject-length': ({ raw }, _when, limit) => {
          const first = firstLines(raw)[0] || '';
          const length = [...first].length;
          return [
            length <= limit || dependabot.test(first),
            `the subject is ${length} characters; the limit is ${limit}`,
          ];
        },
        'ai-workflow/blank-second-line': ({ raw }) => {
          const lines = firstLines(raw);
          return [lines.length < 2 || lines[1] === '', 'the second line must be blank'];
        },
      },
    },
  ],
  rules: {
    'ai-workflow/subject': [2, 'always'],
    'ai-workflow/subject-length': [2, 'always', max],
    'ai-workflow/blank-second-line': [2, 'always'],
    'type-enum': [2, 'always', types],
    'header-max-length': [0],
    'header-trim': [0],
    'subject-case': [0],
    'subject-full-stop': [2, 'never', '.'],
    'body-leading-blank': [0],
    'footer-leading-blank': [0],
    'body-max-line-length': [0],
    'footer-max-line-length': [0],
  },
};
