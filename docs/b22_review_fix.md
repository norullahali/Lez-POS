# B22 REVIEW-FIX

**Date:** 2026-10-08  
**Scope:** F1 and F2 only (dual-connection UPDATE vs VOID concurrency tests)

---

## Baseline

| Check | Result |
|-------|--------|
| Branch | `main` |
| HEAD / origin/main | `53a86e6eea76e9adf15bbc46699890f937aeec12` |
| Staged files | None |
| Production changes in review-fix | **None** |

---

## F1 — UPDATE vs VOID

**Test:** `21) dual-connection update vs void concurrency`

- **Connection A:** `ExpenseMutationSaveService.processUpdate` on `dbA`, held at `beforeMutationHook` until `releaseUpdate`.
- **Connection B:** `ExpenseMutationSaveService.processVoid` on `dbB` runs after barrier; commits while A is paused.
- **Release A:** update resumes, re-reads row, throws `StateError` (`Cannot update voided expense`).

**Final state asserted:**

- Row voided, amount unchanged (50)
- One mutation idempotency seal (void only)
- Summary total 0
- One `expense.voided` activity; zero `expense.updated` mutation activities

---

## F2 — VOID vs UPDATE

**Test:** `22) dual-connection void vs update concurrency`

- **Connection A:** `processVoid` on `dbA`, held at `beforeMutationHook`.
- **Connection B:** `processUpdate` on `dbB` commits while void is paused.
- **Release A:** void applies on the updated row.

**Final state asserted:**

- Row voided, amount 75 (update applied before void)
- Two mutation idempotency seals (update + void)
- Summary total 0
- Exactly one `expense.updated` and one `expense.voided` activity

---

## Deterministic Synchronization

- Two raw SQLite connections via `openDualConnectionRaceDatabases()` (`busy_timeout = 15000`).
- **No** `sleep` / `Future.delayed` for ordering proof.
- B21-style **Completer pair:** `*AtBarrier` signals the test that the held service entered the hook; peer operation runs; `release*` unblocks the held transaction.
- Uses **`ExpenseMutationSaveService` only** (not repository test helpers).

---

## Production Correctness Assessment

| Mechanism | Role |
|-----------|------|
| `beforeMutationHook` | Test-only; production path unchanged |
| UPDATE pre-mutation `getExpenseById` + void guard | Prevents update after void (F1) |
| UPDATE writer `WHERE is_voided = false` | Secondary guard if state changes mid-txn |
| VOID conditional `WHERE is_voided = false` | Idempotent void apply |
| DEFERRED transactions + SQLite locking | Uncommitted work from one connection is not visible to the other; barrier ensures peer commits first |

**No production defect found.** F1 and F2 pass with strict DB-state assertions. No `BEGIN IMMEDIATE` added.

**Note:** Overlap via `preSealHook` (uncommitted mutation) would serialize on locks; the chosen barrier proves the business ordering cases the design cares about (void wins before update starts vs update wins before void starts).

---

## Test Results

| Suite | Result |
|-------|--------|
| B22 full | **22/22 PASS** |

---

## Regression Results

| Suite | Result |
|-------|--------|
| B18 | **20/20 PASS** (with B21 in one run: 42 total) |
| B21 | **22/22 PASS** |
| B4–B10 | **147/147 PASS** |
| B15, B16, B17, B19, B20 | **127/127 PASS** (spot batch) |

---

## Files Changed

| File | Change |
|------|--------|
| `test/expense_mutation_save_protection_b22_test.dart` | Tests 21–22; helpers `activityCountForType`, `seedExpenseOnDualDb`; import `ActivityTypes` |

No `lib/` changes in review-fix.

---

## Optional Findings Left Unchanged

- BUSY/LOCKED integration test
- Migration index assertion
- UI auth widget tests
- UTF-8 BOM in `test/expense_creation_idempotency_b18_test.dart`

---

## Final Verdict

**B22 REVIEW-FIX: READY FOR FINAL AUDIT**