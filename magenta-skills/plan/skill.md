---
name: plan
description: Guide for creating implementation plans. Use when breaking down complex work into actionable steps.
---

# Planning Process for Complex Tasks

When creating a plan for a complex task, follow a structured approach:

- Learning Phase - Understand the codebase
- Architecting Phase - Design the solution
- Writing Phase - Document the plan

## Learning Phase

Before writing the plan, ground yourself in the project as it actually is rather than guessing about the shape of things.

- Identify all the relevant interfaces, types, functions, and APIs the task touches.
- Verify the actual signatures and declarations — don't assume. Use the hover tool and read the real definitions in the codebase.
- Confirm the installed versions of any packages or libraries involved, and check their real APIs rather than relying on memory.
- Study similar existing features and follow their patterns.

## Architecting the Solution

When architecting your solution:

- Prefer simple, minimal data structures over complex ones.
- In situations where performance isn't critical, prefer an approach that's easier to understand.
- Focus on getting a clear solution of the core problem first, leaving performance and other considerations until later.
- Think about how each feature will be tested. Investigate the project to understand what testing approaches are available to you.

## Writing the Plan

Write the plan to `plans/YYYY-MM-DD-<planName>.md` (using the current date), then yield to the parent with the location of the plan file.

The goal of the plan is to communicate understanding, not to script out every keystroke. Focus on the parts of the solution that are hard to get right or easy to get wrong. Trust the implementer to figure out the mechanical details (which files to touch, in what order) from a clear description of the design.

A good plan covers:

### Objective and Context

- Capture everything the user has requested verbatim, without rephrasing, summarizing, or modifying it. This preserves the original intent and any details that might otherwise be lost.
- Then restate, in your own words, what we're trying to accomplish and why.
- Define the key types, interfaces, and entities involved, and how they relate.
- List the relevant files with a short note on each one's role.

### High-Level Design

- Describe the algorithm or system at a conceptual level — the shape of the solution, the main components, and how data flows between them.
- Explain the reasoning behind the approach, and mention alternatives that were considered and rejected.
- State the invariants the design relies on: properties that must hold before, during, and after the change, assumptions the existing code depends on that the new code must preserve, and edge cases or failure modes that must be accounted for.
- Keep this implementation-agnostic where possible: describe *what* happens and *why*, not the exact sequence of edits.

### Staged Approach

Break the work into a sequence of stages. Each stage should bring up an independent, self-contained piece of the solution that can be verified on its own before moving on to the next one.

For each stage, describe:

- **The goal**: what working capability exists once the stage is complete.
- **Verification**: how we'll confirm this stage works before moving on. Identify the key behaviors needing coverage and the kind of test that fits each (unit, integration, etc.). For the important cases, sketch:
  - Behavior: one-sentence description of what's being verified
  - Setup: fixtures, mocks, or state needed
  - Actions: what triggers the behavior
  - Expected outcome: what correctness looks like

At the completion of every stage, verify that the full test suite, type checks, and linting all pass before starting the next stage.

### What to Leave Out

- Don't prescribe an exact, ordered list of file edits unless ordering is genuinely load-bearing.
- Don't restate code that already exists or that the implementer can easily find.
- Don't pad the plan with mechanical detail — favor clarity about the tricky parts over completeness about the obvious ones.

The following shows an example plan structure:

```markdown
# Objective and Context

[The user's request, captured verbatim.]

[What we're building and why, in your own words.]

[The key types, interfaces, and entities involved, and how they relate.]

[The relevant files, each with a one-line description of its role.]

# Design

[A high-level description of the algorithm or system. The main components,
how they interact, and the data flow between them. The reasoning behind the
approach and any alternatives considered.]

Invariants:
- [Property that must hold, e.g. "the cache must never return stale entries
  after an invalidation"]
- [Assumption the current code depends on that we must preserve]
- [Edge case the design must handle]

# Stages

## [name of the first independent piece]

- Goal: [what works once this stage is done]
- Verification:
  - Behavior: [what is being verified]
  - Setup: [fixtures / mocks / state]
  - Actions: [what triggers it]
  - Expected outcome: [what correctness looks like]
- Before moving on: confirm tests, type checks, and linting all pass.

## [name of the next piece, building on the previous one]

- Goal: [...]
- Verification: [...]
- Before moving on: confirm tests, type checks, and linting all pass.
```
