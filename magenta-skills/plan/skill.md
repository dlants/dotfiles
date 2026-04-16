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

Before writing the plan, you may need to learn about relevant parts of the codebase. Follow this learning process:

- Identify all functions, objects and types needed for the task
- List all entities by name
- Explicitly state: "X, Y and Z seem relevant. I will try and learn about them."
- Use the hover tool on each entity to see its signature and declaration location
- If the signature is ambiguous or insufficient, look at the declaration
- Repeat until you have learned about all relevant interfaces

### Learning Phase Example

The following example demonstrates the learning process:

```
user: learn about how to implement feature X in the code
assistant: myFunction1 and myFunction2 seem relevant. I will try to
           learn about them.
[uses hover tool on myFunction1 - shows it's a function in myFile
 that accepts an opaque MyType argument]
[uses hover tool on myFunction2]
[since myFile is not part of the context, uses get_file to look at
 myFile to see full function implementation and where MyType is
 imported from]
MyType seems relevant. I will try to learn about it.
[uses hover on MyType]
[... and so on, until all relevant interfaces have been gathered ...]
```

## Architecting the Solution

When architecting your solution:

- Study similar features in the codebase and follow their patterns.
- Prefer simple, minimal data structures over complex ones.
- In situations where performance isn't critical, prefer an approach that's easier to understand.
- Focus on getting a clear solution of the core problem first, leaving performance and other considerations until later.
- Think about how each feature will be tested. Investigate the project to understand what testing approaches are available to you.

## Writing the Plan

Write the plan to `plans/YYYY-MM-DD-<planName>.md` (using the current date), then yield to the parent with the location of the plan file.

The plan should have two main sections:

Context Section

- Briefly restate the objective
- Explicitly define key types and interfaces
- List relevant files with brief descriptions

Implementation Section

- Provide concrete, discrete implementation steps
- For each step, include a testing section with:
  - Behavior: one-sentence description
  - Setup: fixtures, custom files, options, mock configuration
  - Actions: what triggers the behavior under test
  - Expected output: what the system should produce
  - Assertions: how correctness is verified

The following shows an example plan structure:

```markdown
# context

The goal is to implement a new feature [feature description].

The relevant files and entities are:
[file 1]: [why is this file relevant]
[interface]: [why is it relevant]
[class]: why is it relevant]
[file 2]: [why is this file relevant]
... etc...

# implementation

- [ ] amend [interface] to include a new field
      {[fieldname]: [fieldtype]}
  - check all references of the interface to accommodate the
    new field
  - check for type errors and iterate until they pass
- [ ] write a helper class [class] that performs [function]
  - write the class
  - write unit tests for [class]
    - Behavior: [class] correctly [does X] when given [input]
    - Setup: create [fixture/mock] with [configuration]
    - Actions: call [method] with [arguments]
    - Expected output: [describe expected result]
    - Assertions: verify [specific conditions]
  - iterate until tests pass
- [ ] wire up [class] in the sidebar flow
  - implement the integration
  - write integration test for [user flow]
    - Behavior: user can [do Y] via the [UI]
    - Setup: initialize [component] with [state/config]
    - Actions: [trigger user action or event]
    - Expected output: [describe what the user should see/experience]
    - Assertions: verify [DOM state / API calls / side effects]
  - iterate until integration tests pass
```
