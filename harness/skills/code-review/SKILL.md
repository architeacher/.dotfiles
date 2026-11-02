---
name: code-review
description: 'Use when completing tasks, implementing major features, or before merging to verify work meets requirements.'
disable-model-invocation: true
license: MIT
metadata:
  tags: "SDLC, Code Review, Productivity"
  category: "productivity"
---

# code-review

## When to Use This Skill

Invoke this skill when the user says things like:

- "review it"

- "commit push MR"

- "review this"

- "review an MR/PR"

- "open an MR/PR"

- "commit and push"

Also invoke it when:

**Mandatory:**

- After each development task

- After a major feature completion

- Before merging to main

**Optional but valuable:**

- When stuck (fresh perspective)

- Before refactoring (baseline check)

- After fixing a complex bug

**Core principle:** Review early, review often.

## What to check for?

Dispatch code-reviewer subagents to do the following Steps:

### Step 1 — Sanity checks

* Read the related (Jira/Gitlab/GitHub) ticket/issue with its attachments, comments, linked tickets/issues, and related MR(s).

* Verify that Acceptance Criteria is met in the implemented Code/MR, and provide evidence when not.

* Check that MR(s) is linked to a ticket.

* Decide if MR needs to split: if it's modifying many files >= 38 files, with too many modifications in the same file or too many additions .

* Validate MR is having scope creep; i.e doing extra stuff that is not mentioned in the ticket.

* Focus first on the changes done ONLY by the AUTHOR.

* Consider the BIG PICTURE, by checking the callers of the changed code.

### Step 2 - Architecture review

Evaluate:

* Overall system design and component boundaries.

* Dependency graph and coupling concerns (e.g. Domain layer has external deps., or Application layer doesn't use infrastructure ports).

* Separation of concerns (CQS or CQRS are implemented Properly)

* Data flow patterns and potential bottlenecks.

* Scaling characteristics and single points of failure.

* Security architecture (auth, data access, API boundaries).

### Step 3 - Code quality review

Evaluate:

* Code standards, organization, naming conventions, and module structure.

* SOLID, DRY, KISS, YAGNI, and TDA violations — be aggressive here.

* Error handling patterns and missing edge cases (call these out explicitly).

* Technical debt hotspots.

* Areas that are over-engineered or under-engineered.

## Step 4 - Test review

Evaluate:

* Test coverage gaps (unit, integration, e2e).

* Domain logic coverage (Should be heavily tests).

* Test quality and assertion strength by testing behavior.

* Missing edge case coverage—be thorough.

* Untested failure modes and error paths.

## Step 5 - Security review

Scrutinize:

* Secrets should not be committed

* Input validation, and Output sanitization.

* Vulnerabilities (e.g. SQL injection)

## Step 6 - Performance review

Evaluate:

* N+1 queries and database access patterns.

* DB migrations, are they targeting heavy loaded tables, that will take long time to migrate.

* Memory-usage concerns.

* Caching opportunities.

* Slow or high-complexity code paths.

### Step 7 - Documentation:

Compare with the AgDR:

* New deps / frameworks / libraries / infra components

* Architecture/Desgin patterns

### Step 7 - Reporting:

Wait for all the previous steps to finish and then, do the following:

For every specific issue type (bug, smell, design concern, or risk):

* Mention the file name concatenated with column and the line number (e.g., `src/foo/bar.rs:888`)

* Present 2–3 options, including “do nothing” or what should be the fix as a code diff (if not a single liner).

* For each option, specify: implementation effort, risk, impact on other code, and maintenance burden.

* For complicated scenarios, show the stack trace.

* Group the AUTHOR changes by (file name → issue type DESC)

* Group the BIG PICTURE changes (if not mentioned before) by (file name → issue type DESC)

## Red Flags

**Never:**
- Skip review because "it's simple"

- Ignore Critical issues

- Proceed with unfixed Important issues

- Argue with valid technical feedback

See template at: `code-reviewer.md`
