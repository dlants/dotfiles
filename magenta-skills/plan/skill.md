---
name: plan
description: Guide for creating implementation plans. Use when breaking down complex work into actionable steps.
---

# Planning Process for Complex Tasks

When creating a plan for a complex task, follow a structured approach:

1. Learning Phase - Understand the codebase
2. Architecting Phase - Design the solution
3. Writing Phase - Document the plan

## Learning Phase

Before writing the plan, you may need to learn about relevant parts of the codebase. Follow this learning process:

1. Identify all functions, objects and types needed for the task
2. List all entities by name
3. Explicitly state: "X, Y and Z seem relevant. I will try and learn about them."
4. Use the hover tool on each entity to see its signature and declaration location
5. If the signature is ambiguous or insufficient, look at the declaration
6. Repeat until you have learned about all relevant interfaces

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

### Study similar features

Study similar features in the codebase and follow their patterns.

### Prefer simplicity

Prefer simple, minimal data structures over complex ones.

### Avoid premature optimization

In situations where performance isn't critical, prefer an approach that's easier to understand.

For example, when preparing a network request, you're already dealing with something that's on the order of 100ms. You can recompute request arguments rather than creating state to cache them.

When introducing state or a cache, consider whether the performance gained from storing these is worth the complexity of maintaining them.

### Focus on the core problem

Focus on getting a clear solution of the core problem first, leaving performance and other considerations until later.

### Consider testing

Think about how each feature will be tested. Investigate the project to understand what testing approaches are available to you.

## Writing the Plan

Write the plan to `plans/YYYY-MM-DD-<planName>.md` (using the current date), then yield to the parent with the location of the plan file.

### Plan Structure

The plan should have two main sections:

#### Context Section

- Briefly restate the objective
- Explicitly define key types and interfaces
- List relevant files with brief descriptions

#### Implementation Section

- Provide concrete, discrete implementation steps
- For each step, include a testing section with:
  - Behavior: one-sentence description
  - Setup: fixtures, custom files, options, mock configuration
  - Actions: what triggers the behavior under test
  - Expected output: what the system should produce
  - Assertions: how correctness is verified

### Plan Structure Example

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
  - [ ] check all references of the interface to accommodate the
          new field
  - [ ] check for type errors and iterate until they pass
- [ ] write a helper class [class] that performs [function]
  - [ ] write the class
  - [ ] write unit tests for [class]
    - [class] correctly [does X] when given [input]
  - [ ] iterate until tests pass
- [ ] wire up [class] in the sidebar flow
  - [ ] implement the integration
  - [ ] write integration test for [user flow]
    - user can [do Y] via the [UI]
  - [ ] iterate until integration tests pass
```
