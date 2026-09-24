# Customer Returns Phase C — Step 2.8B Database Integrity

## Purpose

Step 2.8B hardens invoice-linked `customer_returns` header integrity at the database layer. The goal is exactly one header per sales invoice for partial and full return flows, even when concurrent transactions race on header creation.

The audited **local active Lez POS store database** had zero duplicate non-NULL `original_invoice_id` groups before this migration. Remote production was **not** audited.

## Schema 33

- Previous schema: **32** (Step 2.8A / Step 2.7A baseline)
- Current schema: **33**
- No column changes; `original_invoice_id` remains nullable.

## Partial UNIQUE Index

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_returns_original_invoice
ON customer_returns(original_invoice_id)
WHERE original_invoice_id IS NOT NULL;
```

- Enforced on **fresh installs** (`onCreate`) and on **upgrade** from schema `< 33`.
- Drift table declaration in `customer_returns_table.dart` documents the index for schema consistency.

## NULL Semantics

The partial index applies only where `original_invoice_id IS NOT NULL`.

Multiple rows with `original_invoice_id = NULL` remain valid for manual returns and quick returns. The index does not cover NULL rows.

## Conflict-Aware Upsert

`ReturnsDao.upsertPartialReturnDocumentHeader()`:

1. Fast-path SELECT when a header already exists → increment total.
2. Otherwise `INSERT OR IGNORE` a new header.
3. If insert was ignored (unique conflict) → re-SELECT by `original_invoice_id` → increment total → return existing header ID.

This runs inside the caller's existing transaction. It does **not** use `insertOnConflictUpdate()` because totals must accumulate (`existing.total + batchGoodsTotal`), not replace.

## Concurrency Behavior

When two connections race on the same invoice:

- One `INSERT OR IGNORE` creates the header.
- The other is ignored, recovers the existing row, and increments total.
- Result: one header, combined total, no UNIQUE exception surfaced to callers.

SQLite write lock contention (`SQLITE_BUSY`) is distinct from UNIQUE conflict; this step does not add broad retry infrastructure.

## Migration Safety

Migration v33:

1. Pre-flight duplicate gate on non-NULL `original_invoice_id` groups — throws `StateError` if duplicates exist (no automatic merge/cleanup).
2. Creates the partial UNIQUE index.

Preserves all existing rows, NULL headers, `settled_amount`, foreign keys, `customer_return_items`, `customer_transactions`, and refund architecture. No backfill or duplicate cleanup.

## Full Return Compatibility

`ReturnsDao.returnFullSaleInvoice()` unchanged. Existing duplicate guard remains; UNIQUE index is the database backstop.

## Partial Return Compatibility

Only header creation race behavior changed. Stock, RETURN transactions, invoice status, and item-level return logic are unchanged.

## Refund Compatibility

No changes to refund settlement, aggregate credit guard, `customer_transactions`, or ledger posting. The UNIQUE index guarantees one invoice-linked return document only.

## Tests

Focused suite: `test/customer_returns_database_integrity_phase_c_step_2_8b_test.dart`

## Deferred Work

- Remote/production duplicate audit and remediation (if any duplicates exist outside the audited local DB).
- Broad SQLITE_BUSY retry policy (explicitly out of scope for 2.8B).
- `PosSaleService.processReturn` removal (zero call sites; excluded from this step).