---
name: review
description: Guidance on how to review and un-slopify code.
---

# Redundancy

AI tends to introduce many redundancies: types that express similar concepts, functions that do similar things, many different vehicles for the same idea. AIs don't seem to do a good job of noticing patterns and consolidating — each new requirement gets a new mechanism built next to the old one rather than routed through it.

Look for:

- Types that describe the same underlying data with different field names or different levels of strictness.
- Functions that serve the same purpose, but have slightly different nomenclature or argument / return contracts.
- The same underlying operation reachable by several routes: a wrapped version, a differently-wrapped version, and the raw call.
- Logic duplicated inline rather than calling the helper that already exists for it. Especially constants and sentinels re-spelled at the use site instead of coming from the thing that owns them.

# Premature complexity

We tend to introduce general types and abstractions that make the code more complicated and reduce locality and readability. In most cases, getting rid of the abstraction and generic boilerplate and inlining the code directly as a switch statement or conditional is better.

Look for:

- Data-driven loops over a fixed, known list — a table of tuples iterated over, when a straight sequence of statements would say the same thing and be greppable.
- Configuration objects, option bags, and parameter structs whose fields are all set to the same values at every call site.
- Type parameters with exactly one instantiation.
- Helpers that exist only to hold a two-line body, especially when the wrapper obscures what permission, lock, or side effect is actually in play.
- Optional-pair parameters (`{ a?: X, b?: Y }`) where every caller knows exactly which one it has. That's a disjoint union at best, and two separate functions at worst.
- private functions that are only used once. These should just be inlined.

# Naming

A proliferation of names for the same thing. We should define a single term for a concept and use it consistently — across types, fields, functions, database columns, and prose.

When you find one, pick the term that the domain actually uses and rename everything else to it. Don't split the difference.

# Pointless indirection

Passing functions or getters when you could just pass an object. Wrapping things in an abstract class when you could just represent it as a branch over the data shape.

Look for:

- Callbacks, thunks, and getters where the value is already available and unchanging. A lazily-supplied value that is never lazily used.
- Class hierarchies, interface implementations, or the visitor pattern standing in for what the data already tells you. If the branch is on a tag the data carries, write the switch.
- Objects that exist to hold a single method, or that imitate the shape of a nearby abstraction without participating in it — cargo-culted structure that makes a thing look like it's part of a system it isn't part of.
- Identity functions and pass-through wrappers, particularly ones whose doc comments argue for their own existence. A comment defending a function is strong evidence the function shouldn't be there.
- Layers that only forward: a function whose entire body is a call to another function with the same arguments.

# Leftover artifacts

Editing at a distance leaves debris that a human editing in place would not produce.

- Doc comments orphaned from the declaration they described, left behind when that declaration moved or was renamed.
- Comments that restate the code rather than explaining why it exists.
- Re-exports and imports stranded in the middle of a file, marking where something used to live.
- Hand-maintained lists (arrays of enum members, registries, allow-lists) that duplicate a type and will silently drift from it. Ask whether the type can generate the list, or whether a compile-time check can bind them.
- Asymmetric handling of symmetric cases: two adjacent functions doing the same kind of thing where one is exhaustive and the other has a catch-all, or one throws and the other returns a default.
- References to code as it used to be. "X, never Y". "Not this". That's no longer relevant - we don't see the history of the file in the file. If we wanted to, we could look at the git history.
