# Customer Returns Phase C — Step 3.0: Refund Idempotency

## Objective

Implement persistent financial idempotency for customer REFUND settlement so duplicate submit/retry/concurrent requests with the **same operation key** cannot create a second REFUND row.

## Key lifecycle

- UUID v4 generated once in `CustomerRefundSettlementUiNotifier.init()` per dialog open.
- Amount/note edits, client validation failures, and service failures keep the same key.
- Retries after timeout/lost response reuse the same key.
- Success closes/resets the dialog; cancel discards the key; reopen generates a new key.

## Database design

Schema **34** adds `customer_refund_idempotency`:

| Column | Type | Notes |
|--------|------|-------|
| idempotency_key | TEXT PK | Operation identity |
| customer_id | INTEGER NOT NULL | Fingerprint |
| amount | REAL NOT NULL | Fingerprint |
| return_id | INTEGER NULL | Fingerprint |
| note | TEXT NOT NULL DEFAULT '' | Fingerprint (`trim()`, null → '') |
| customer_transaction_id | INTEGER NOT NULL | Original REFUND row id |
| created_at | INTEGER NOT NULL | Drift DateTime storage |

Index: `cri_customer_created_idx (customer_id, created_at)`

## Migration

- Fresh install: table + index created with schema 34.
- v33 → v34: `customer_refund_idempotency` table and index via migration block in `app_database.dart`.
- No backfill for historical REFUND rows.

## Replay semantics

Within one Drift transaction:

1. Lookup idempotency key.
2. If found and fingerprint matches → return original `customerTransactionId`, `idempotentReplay: true`, **no financial mutation**.
3. Otherwise run existing validation, aggregate guard (2.8A), REFUND insert, per-return cap (2.7B), audit log.
4. Insert idempotency row and commit.

Replay is treated as success in UI (invalidate displays, close dialog).

## Mismatch policy

Same key with different `customerId`, `amount`, `returnId`, or normalized `note` throws `idempotencyKeyConflict` with Arabic UX message. No silent parameter application.

## Transaction boundary

`CustomerRefundSettlementService.settleCredit()` remains the **sole** REFUND mutation boundary. `CustomerRefundIdempotencyDao` is read/record support only inside the service transaction.

## Concurrency behavior

- PRIMARY KEY on `idempotency_key` is authoritative.
- Concurrent first-time same-key requests: one transaction seals the key; competing insert hits UNIQUE → rollback → re-read → replay or conflict.

## Design addendum: local SQLITE_BUSY retry (Step 3.0 hardening)

The approved design excluded a **broad** SQLITE_BUSY retry framework. Step 3.0 adds a **narrow, local** retry loop inside `CustomerRefundSettlementService.settleCredit()` only, because dual-connection same-key concurrent tests fail without it even when `PRAGMA busy_timeout` is set on the raw SQLite handles.

This is **not** a global retry framework and does not change SQLITE_BUSY handling elsewhere in the app.

| Property | Value |
|----------|-------|
| Scope | `settleCredit()` outer loop only |
| Trigger | Error message contains `database is locked` or `SqliteException(5)` |
| Attempts | 8 (attempt indices 0–7) |
| Backoff | 25 × (attempt + 1) ms → 25, 50, 75, …, 175 ms |
| Non-lock errors | Not retried; immediate `unexpectedFailure` after first catch |

### Safety rationale

A. **No repeat of committed financial mutation** — each retry starts a fresh Drift transaction. If the winning peer already committed the idempotency row, the retry path hits the lookup branch and returns `idempotentReplay: true` with **no REFUND insert**.

B. **Failed transactions fully rollback** — any SQLITE_BUSY during `_db.transaction()` aborts that transaction; REFUND, settled_amount, audit, and idempotency rows from that attempt are rolled back together.

C. **Retry after REFUND in a failed attempt** — the REFUND from the rolled-back attempt is not visible to other connections after rollback. A retry either seals anew or replays the winner.

D. **Idempotency lookup prevents second mutation** — once sealed, all same-key calls with matching fingerprint replay without mutation.

E. **UNIQUE seal race remains deterministic** — idempotency INSERT UNIQUE failure throws `_IdempotencySealRace`, rolls back the whole transaction, and re-enters the outer loop for replay lookup.

F. **Non-lock errors are not masked** — only `_isSqliteBusyOrLocked()` matches trigger retry; other exceptions surface as `unexpectedFailure`.

G. **Strictly local** — no shared retry utility, no DAO-level retry, no provider/UI retry.

H. **No effect outside refunds** — no other service or DAO was modified for busy handling.

### Removal criterion

PATH 1 (remove retry) was tested during hardening: concurrent same-key tests **fail** without this loop. Retry is therefore **kept and formalized** here rather than expanded globally.

## Tests

`test/customer_refund_idempotency_phase_c_step_3_0_test.dart` covers scenarios A–P (sequential replay, concurrent connections, conflicts, partial refunds, failures, migration, historical rows).

## Deferred limitation

Idempotency keys are **session/dialog scoped** only. Cross-session or cross-dialog persistence is intentionally out of scope (Step 3.0).