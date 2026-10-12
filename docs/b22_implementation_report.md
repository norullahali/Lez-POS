# B22 Implementation Report — Expense Update and Void Save Protection

**Baseline:** `53a86e6` @ schema v48  
**Target schema:** v49  
**Status:** Implementation complete — READY FOR REVIEW

## Production path

- **Update:** `ExpenseDialog` → `ExpenseMutationSaveService.processUpdate`
- **Void:** `ExpenseScreen._ActionButtons` → `ExpenseMutationSaveService.processVoid`
- **Create (unchanged):** `ExpenseCreationService` / B18

## Schema v49

- Table `expense_mutation_idempotency` (UPDATE + VOID only)
- Index `emi_expense_record_idx` on `expense_record_id`
- Additive migration v48→v49, no backfill

## Idempotency

- Same key + same fingerprint → replay (no row/audit mutation)
- Same key + different fingerprint → `ExpenseMutationSaveIdempotencyConflictException`
- Void on already-voided row (different key) → no mutation, no seal, no extra audit

## Auth

- UI and service require `userId > 0` for update/void
- Fingerprints include `updatedBy` / `voidedBy`

## Audit

- Update: in-txn info log
- Void: in-txn **warning** log

## Tests

- `test/expense_mutation_save_protection_b22_test.dart`: **20/20 PASS**
- B18: **20/20 PASS** (tests 13–14 use test-only repository helpers)
- B21: **22/22 PASS**
- B4–B10: **147/147 PASS**

## Regression schema

- 14 regression test files bumped to schema **49** only

## Optional follow-ups

- Additional B22 cross-path concurrency tests (update↔void overlap)
- POS debt settlement sticky key (R3)
- Other income mutation protection (B23)