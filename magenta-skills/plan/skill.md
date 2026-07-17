---
name: plan
description: Guide for creating plans for tackling complex work.
---

Before writing the plan, ground yourself in the project as it actually is rather than guessing about the shape of things.

- Identify all the relevant interfaces, types, functions, and APIs the task touches.
- Verify the actual signatures and declarations — don't assume. Use the hover tool and read the real definitions in the codebase.
- Confirm the installed versions of any packages or libraries involved, and check their real APIs rather than relying on memory.
- Study similar existing features to be informed about patterns you can follow.

When architecting your solution:

- Follow established codebase patterns.
- Prefer simple, minimal data structures over complex ones.
- In situations where performance isn't critical, prefer an approach that's easier to understand.
- Focus on getting a clear solution of the core problem first, leaving performance and other considerations until later.
- Think about how each feature will be tested. Investigate the project to understand what testing approaches are available to you.

# Plan structure

Write the plan to `plans/YYYY-MM-DD-<planName>.md` (using the current date).

```markdown
# Objective and Context

[The user's request, captured verbatim.]

[The key types, interfaces, and entities involved, and how they relate.]

[The relevant files, each with a one-line description of its role.]

# Design

[A high-level description of the algorithm or system. The main components, how they interact, and the data flow between them. The reasoning behind the approach and any alternatives considered.]

Invariants:

- [Property that must hold, e.g. "the cache must never return stale entries after an invalidation"]
- [Assumption the current code depends on that we must preserve]
- [Edge case the design must handle]

# Stages

## [stage name that summarizes it in a few words like "backend" or "preparing type system"]

- Goal: [what works once this stage is done]
- Tests:
  - When we do x, y should happen.
  - Unit tests that just restate what the code is doing are insufficient.
  - Consider where the complexity of this implementation lives.
  - If the hard part is in how the existing code integrates with the surrounding context, then verify the integration directly.

## [stage name]

- Goal: [...]
- Tests: [...]
```
