## Local override (ai-workflow)

Ask one question per message, not a whole round. Pick the frontier question that unblocks the most other decisions, give your recommended answer, and wait for the reply before the next one.

Each recommended answer also proposes how binding the decision is: `instruction` (follow it; ask before changing it), `preference` (the default; deviate only with a stated reason) or `idea` (open to challenge). A "yes" accepts the level with the answer. Never ask about levels in a separate round.

Mark each fact in a recommended answer checked (with its source) or from memory. A fact that matters and that a few searches can settle is checked before you ask. A bigger one becomes background research (the `researching` skill), and the question that depends on it waits while you ask the others. A decision that rests on memory is recorded as `assumed`.

Everything else above still applies.
