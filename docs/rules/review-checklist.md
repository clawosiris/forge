# Pre-Landing Review Checklist

## Instructions

Review the diff between the implementation branch and main. Be specific — cite `file:line` and suggest fixes. Skip anything that's fine. Only flag real problems.

**Two-pass review:**
- **Pass 1 (CRITICAL):** Memory safety, data integrity, concurrency, security. Highest severity.
- **Pass 2 (INFORMATIONAL):** Test gaps, dead code, performance, completeness. Lower severity but still actioned.

All findings get action via Fix-First Review: obvious mechanical fixes are applied automatically, genuinely ambiguous issues are batched into a single user question.

**Output format:**

```
Pre-Landing Review: N issues (X critical, Y informational)

**AUTO-FIXED:**
- [file:line] Problem → fix applied

**NEEDS INPUT:**
- [file:line] Problem description
  Recommended fix: suggested fix
```

If no issues found: `Pre-Landing Review: No issues found.`

Be terse. For each issue: one line describing the problem, one line with the fix. No preamble, no summaries, no "looks good overall."

---

## Review Categories

### Pass 1 — CRITICAL

#### Memory & Resource Safety (Rust)
- `unsafe` blocks without safety comments explaining invariants
- Raw pointer dereferencing without bounds validation
- Missing `Drop` implementations for types holding external resources
- `mem::forget` on types that own resources (leaks)
- `transmute` between types with different layouts or lifetimes
- FFI calls without proper null checks or error handling

#### Data Integrity
- `.unwrap()` or `.expect()` on user-controlled input (panic in production)
- Missing validation at API boundaries (trust boundaries)
- Serialization/deserialization without schema validation
- Database operations without transaction boundaries where atomicity matters
- TOCTOU races: check-then-act patterns that should be atomic

#### Concurrency & Thread Safety
- Shared mutable state without `Mutex`/`RwLock` or `Arc<Mutex<_>>`
- `RefCell` or `Cell` used across threads (UB)
- Lock ordering inconsistency (deadlock risk)
- Missing `Send`/`Sync` bounds on types crossing thread boundaries
- Blocking calls inside async contexts without `spawn_blocking`

#### Error Handling
- `?` propagation losing error context (should use `.context()` or `.map_err()`)
- Swallowed errors: `let _ = potentially_failing_call()`
- Panic-inducing patterns in library code (libraries should return `Result`)
- Missing error variants for recoverable failure modes
- `todo!()` or `unimplemented!()` in non-prototype code paths

#### Security
- Hardcoded secrets, API keys, or credentials
- User input passed to shell commands without escaping
- SQL query construction without parameterization
- Cryptographic operations using non-constant-time comparisons
- Path traversal: user input in file paths without canonicalization
- Deserialization of untrusted data without type constraints

#### Enum & Match Completeness
When the diff introduces a new enum variant or status value:
- **Trace every `match` expression.** Does the new variant fall through to `_` wildcard? Is that correct?
- **Check exhaustive matches.** If any match is non-exhaustive and relies on `_`, verify the new variant should use the default behavior.
- **Check Display/Debug/Serialize implementations.** Are they updated for the new variant?
- **Search for string comparisons.** Anywhere comparing against the old variant names?

### Pass 2 — INFORMATIONAL

#### Test Gaps
- Public API functions without test coverage
- Error paths without negative tests
- Edge cases mentioned in spec without corresponding tests
- Integration tests missing for cross-component behavior
- Tests asserting only happy path, not error messages or side effects

#### Completeness Gaps
- Partial implementations where the complete version is <30 min additional work
- Error messages that don't include actionable context (what failed, why, what to do)
- Documentation gaps for public API
- Missing `Debug` or `Display` implementations for public types
- `// TODO` comments for features that should be in this PR per spec

#### Dead Code & Consistency
- Unused imports, functions, or type definitions
- Comments describing old behavior after code changed
- Version mismatch between Cargo.toml, CHANGELOG, and PR title
- Inconsistent naming (snake_case vs camelCase mixing)
- Duplicate implementations that could share code

#### Performance
- `.clone()` in hot paths where borrowing would work
- Allocations inside loops that could be hoisted
- O(n²) algorithms where O(n log n) or O(n) is straightforward
- Missing `#[inline]` on small hot functions
- Large types passed by value instead of reference

#### API Design
- Breaking changes without major version bump
- Missing `#[must_use]` on Result-returning functions
- Public API exposing internal implementation details
- Inconsistent error types across similar functions
- Missing builder pattern for types with many optional fields

#### Dependencies
- New dependencies without justification in PR description
- Heavyweight dependencies for simple functionality
- Dependencies with known security advisories
- Duplicate functionality already available in existing deps

---

## Severity Classification

```
CRITICAL (highest severity):          INFORMATIONAL (lower severity):
├─ Memory & Resource Safety           ├─ Test Gaps
├─ Data Integrity                     ├─ Completeness Gaps
├─ Concurrency & Thread Safety        ├─ Dead Code & Consistency
├─ Error Handling                     ├─ Performance
├─ Security                           ├─ API Design
└─ Enum & Match Completeness          └─ Dependencies

All findings are actioned via Fix-First Review. Severity determines
presentation order and classification of AUTO-FIX vs ASK — critical
findings lean toward ASK, informational findings lean toward AUTO-FIX.
```

---

## Fix-First Heuristic

```
AUTO-FIX (agent fixes without asking):       ASK (needs human judgment):
├─ Unused imports / dead code                ├─ Security changes
├─ Missing .context() on error propagation   ├─ Concurrency / thread safety
├─ Missing #[must_use] attributes            ├─ Design decisions (API shape)
├─ Stale comments contradicting code         ├─ Large refactors (>20 lines)
├─ Adding Debug/Display derives              ├─ Enum completeness across codebase
├─ Formatting / clippy lints                 ├─ Breaking API changes
├─ Missing documentation on public items     ├─ Removing functionality
└─ Simple test additions for coverage        └─ Performance tradeoffs
```

**Rule of thumb:** If the fix is mechanical and a senior engineer would apply it without discussion, it's AUTO-FIX. If reasonable engineers could disagree about the fix, it's ASK.

---

## Suppressions — DO NOT flag these

- Clippy lints that are project-specifically allowed (check clippy.toml or lib.rs attributes)
- `.unwrap()` in test code (tests should panic on unexpected failures)
- `// TODO` comments for out-of-scope follow-up work documented in the issue
- "Could be more idiomatic" suggestions that don't affect correctness
- Performance optimizations for cold paths
- Missing documentation on internal/private items
- "Add a comment explaining why" for values that are tuned empirically
- ANYTHING already addressed in the diff you're reviewing — read the FULL diff before commenting
