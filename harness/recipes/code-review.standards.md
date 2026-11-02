# Code Review Standards

Every check that `code-reviewer` applies. Each `##` section is one Focus key of
`${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/agents/code-reviewer.md`.

A standard documented in the repository under review overrides this file. When the repository endorses something
listed here, suppress the finding. Skip purely stylistic issues (formatting, whitespace, import order) and anything
that tooling (linters, formatters, type checkers) already enforces.

## Architecture & Design

- Layers and modules respect agreed boundaries: the domain layer has no external dependencies, and the application
  layer reaches infrastructure only through ports.

- Responsibilities are well-factored and cohesive.

- Cross-cutting concerns (logging, caching, validation, transactions) are handled in the right places.

- Side effects and domain events are modeled and triggered in a predictable way.

- Separation of concerns: CQS or CQRS implemented properly.

- Data flow patterns and potential bottlenecks.

- Scaling characteristics and single points of failure.

- Security architecture: auth, data access, API boundaries.

## Code Quality

- Type safety and explicitness where the language supports it. No untyped or weakly typed escapes without
  justification.

- Reasonable function and method size.

- Consistent naming conventions across variables, functions, classes, and modules.

- Proper error handling: no swallowed errors, no unlogged failures.

- SOLID, KISS, and TDA violations that the smell baseline below does not name. Report every one.

- Module structure and organization.

- Technical debt hotspots.

- Areas that are under-engineered. Over-engineering is Speculative Generality below.

### Smell baseline

Fowler code smells (_Refactoring_, ch. 3). Each smell is a judgement call, never a hard violation: label it
"possible <smell>", quote the hunk, and keep it advisory. Each reads *what it is* → *how to fix*.

- **Mysterious Name**: a function, variable, or type whose name does not reveal what it does or holds. → Rename
  it. If no honest name comes, the design is unclear.

- **Duplicated Code**: the same logic shape appears in more than one hunk or file of the change. → Extract the
  shared shape and call it from both.

- **Feature Envy**: a method that uses another object's data more than its own. → Move the method onto the data it
  envies.

- **Data Clumps**: the same few fields or parameters travel together. → Bundle them into one type and pass that.

- **Primitive Obsession**: a primitive or string stands in for a domain concept. → Give the concept its own small
  type.

- **Repeated Switches**: the same `switch` or `if` cascade on the same type recurs across the change. → Replace it
  with polymorphism, or with one map that both sites share.

- **Shotgun Surgery**: one logical change forces scattered edits across many files. → Gather what changes together
  into one module.

- **Divergent Change**: one file or module is edited for several unrelated reasons. → Split it so that each module
  changes for one reason.

- **Speculative Generality**: abstractions, parameters, or hooks for needs the ticket does not have. → Delete them,
  and inline until a real need appears.

- **Message Chains**: long `a.b().c().d()` navigation that the caller should not depend on. → Hide the walk behind
  one method on the first object.

- **Middle Man**: a class or function that mostly delegates onward. → Remove it and call the real target directly.

- **Refused Bequest**: a subclass or implementer that ignores or overrides most of what it inherits. → Drop the
  inheritance and use composition.

## Testing

- Core domain and business logic is heavily unit-tested.

- Integration or end-to-end coverage for important use cases.

- Tests and their assertions check **observable behavior**, not internal implementation details or only that the
  code ran.

- Edge cases, boundary conditions, and error paths are covered.

- The MR/PR body or docs show that tests ran and are meaningful, or explain why no tests apply (for example,
  docs-only changes). Treat this as a claim until the affected tests have been run.

## Security

Flag clear issues and suspicious patterns. This is not a full security audit.

- No hard-coded secrets or credentials.

- Input validation and sanitization, especially across trust boundaries.

- Output sanitization and encoding.

- No injection vectors (SQL, NoSQL, command injection).

- No cross-site scripting or similar client-side issues, where relevant.

- Correct use of authentication and authorization.

## Performance

- No N+1 patterns or unnecessary repeated work.

- DB access patterns beyond N+1: query shape, missing indexes, transaction scope.

- DB migrations that target heavily loaded tables: lock duration and migration time.

- Data structures and algorithmic complexity fit the expected scale.

- No blocking or synchronous operations in known hot paths.

- Reasonable payload sizes and resource usage for APIs and batch jobs.

- Memory-usage concerns.

- Caching opportunities.

## MR/PR Scope & Description

All checks in this section are advisory.

- A clear, concise summary of what changed and why.

- A link to the relevant ticket or issue.

- Reviewable in one pass. Suggest a split when the diff exceeds the split threshold, when one file carries most of
  the churn, or when the diff has too many additions.

- A **Glossary section** when the change introduces new terms, patterns, or acronyms.

- Summary bullets are narrative: each answers what changed and why it matters to the reader. Label-only bullets
  (for example, "CI updates") get a `nit:`.

## Technical Decisions

A **material technical decision** is one of:

- A new dependency, framework, library, or infrastructure component.

- A new or changed storage technology.

- A major architecture or design pattern.

- A cross-cutting change that is hard to reverse.

Routine, easily reversible implementation choices are not material.

For each material decision:

- It is explained in the MR/PR description or a design note, clearly enough for future reviewers.

- Find it in the decision records (for example `docs/architecture.md`, `docs/adr/`, `docs/agdr/`, or records the
  orchestrator passes), and check that the record matches the code.

- Without any recorded rationale, ask for a short design note or decision record.
