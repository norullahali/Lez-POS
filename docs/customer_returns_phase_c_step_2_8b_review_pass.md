# Customer Returns Phase C — Step 2.8B Review Pass

## 1. Baseline

| Item | Value |
|------|-------|
| Step 2.8A baseline commit | `1b52d9e` |
| Step 2.8B schema | 32 → **33** |
| Review mode | Read-only (no code/test/doc edits) |

Approved design: partial UNIQUE index on non-NULL `original_invoice_id`; conflict-aware header upsert (`SELECT` → `INSERT OR IGNORE` → re-`SELECT` → increment total); no broad `SQLITE_BUSY` retry; refund architecture unchanged; `PosSaleService.processReturn` excluded.

## 2. Scope

### Tracked modifications (`git diff` vs HEAD)

| File | Δ | Verdict |
|------|---|---------|
| `lib/core/database/app_database.dart` | +40 / −1 | **In scope** — schema 33, onCreate index, v33 migration |
| `lib/core/database/daos/returns_dao.dart` | +40 / −4 | **In scope** — conflict-aware upsert only |
| `lib/core/database/tables/customer_returns_table.dart` | +9 | **In scope** — Drift index declaration |
| `test/customer_return_settlement_state_phase_c_step_2_7a_test.dart` | +2 / −2 | **In scope** — schema expectation 32→33 |

### Untracked (working tree)

| File | Verdict |
|------|---------|
| `test/customer_returns_database_integrity_phase_c_step_2_8b_test.dart` | **In scope** — Step 2.8B focused suite |
| `docs/customer_returns_phase_c_step_2_8b_database_integrity.md` | **In scope** — implementation doc |
| Other untracked `docs/customer_returns_phase_c_*` and `tool/_write_2_7c_test.dart` | **Out of Step 2.8B diff** — prior-phase artifacts; not modified during review |

**No unrelated production file changes** detected in tracked diff. Financial architecture files unchanged since `1b52d9e`.

## 3. Schema 33

| Check | Result |
|-------|--------|
| `schemaVersion == 33` | **PASS** |
| Migration block `from < 33` only | **PASS** |
| Duplicate pre-flight query before index | **PASS** — throws `StateError` with group count |
| Automatic merge/cleanup | **PASS** — none |
| Partial UNIQUE index creation | **PASS** |
| Row preservation | **PASS** — no UPDATE/DELETE of existing data |
| `original_invoice_id` nullable | **PASS** — column unchanged |
| `settled_amount` intact | **PASS** — no v33 column changes |
| Unrelated migration edits | **PASS** — v33 block only |
| Fresh install (`onCreate`) | **PASS** — explicit `CREATE UNIQUE INDEX … WHERE … IS NOT NULL` after `createAll()` |

## 4. Unique Index

Verified SQL (onCreate, migration v33, and Drift table declaration):

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_returns_original_invoice
ON customer_returns(original_invoice_id)
WHERE original_invoice_id IS NOT NULL
```

| Property | Result |
|----------|--------|
| Index name stable | **PASS** — `uq_customer_returns_original_invoice` |
| Non-NULL invoice IDs unique | **PASS** — enforced by partial UNIQUE index + tests G, F-dup |
| Multiple NULL allowed | **PASS** — test F, migration test R |
| No full-table UNIQUE replacing partial | **PASS** — partial index only; column remains nullable |

## 5. Conflict-Aware Upsert

`ReturnsDao.upsertPartialReturnDocumentHeader()` audited:

| Path | Implementation | Result |
|------|----------------|--------|
| Existing header | `findCustomerReturnByOriginalInvoiceId` → `_incrementCustomerReturnHeaderTotal` → return ID | **PASS** |
| New header | `INSERT OR IGNORE` via `InsertMode.insertOrIgnore` | **PASS** |
| Successful insert | `insertedId != 0` → return ID | **PASS** |
| Conflict | re-SELECT → `_incrementCustomerReturnHeaderTotal` → return existing ID | **PASS** |
| Race-prone plain INSERT | **Removed** | **PASS** |
| `insertOnConflictUpdate` | **Not used** | **PASS** |
| Total accumulation | `header.total + batchGoodsTotal` (re-read before write) | **PASS** — not replacement |
| Nested transaction | **None** in DAO | **PASS** |
| Caller transaction | `PartialReturnService` wraps full partial return in `_db.transaction` | **PASS** |

## 6. Concurrency

| Check | Result |
|-------|--------|
| Two SQLite connections on same file | **PASS** — test H |
| Exactly one header after race | **PASS** |
| Combined total (20 + 30 = 50) | **PASS** |
| UNIQUE exception surfaced to caller | **PASS** — none; conflict recovered |
| Lost update | **PASS** — none observed |
| Broad `SQLITE_BUSY` retry infrastructure | **PASS** — not introduced in production |
| `PRAGMA busy_timeout` in test only | **PASS** — test H setup only |

**Note (NON-BLOCKING):** Test H exercises concurrent upsert semantics via raw SQLite SQL mirroring the DAO pattern, not dual-connection Drift calls to `upsertPartialReturnDocumentHeader()`. Full `processPartialReturn` dual-connection was intentionally avoided after `SQLITE_BUSY` on downstream tables in implementation. Integration coverage for stock, `sale_item_returns`, and RETURN accounting remains in sequential partial-return tests (2.6 carryover cases).

## 7. Transaction Atomicity

`PartialReturnService.processPartialReturn` runs steps 1–9 inside `_db.transaction()` including header upsert, items, stock, audit, RETURN posting, and status refresh.

| Check | Result |
|-------|--------|
| Upsert inside caller transaction | **PASS** |
| No nested DAO transaction | **PASS** |
| Rollback on forced credit failure | **PASS** — test `Q) rollback removes customer_returns and sale_item_returns on failure` clears header, items, sale_item_returns, RETURN txns, restores stock |

## 8. Full Return Regression

`returnFullSaleInvoice()` diff: **unchanged** in Step 2.8B.

| Scenario | Result |
|----------|--------|
| Clean full return → one header | **PASS** — test L |
| Partial → full → same header | **PASS** — test K |
| Duplicate guard (`dup != null` throw) | **PASS** — still present |
| Partial path delegates to `returnAllRemainingSaleInvoice` | **PASS** — unchanged |

## 9. NULL Semantics

| Check | Result |
|-------|--------|
| Column nullable in schema | **PASS** |
| Multiple NULL headers insertable | **PASS** — test F |
| Migration preserves NULL headers | **PASS** — test R |
| Partial index excludes NULL | **PASS** |

## 10. Financial Architecture

Verified **zero diff** since `1b52d9e` for:

- `CustomerRefundSettlementService`
- `CustomerAccountsDao`
- `partial_return_service.dart` (caller only; upsert call unchanged except DAO behavior)
- Refund / ledger / settlement UI modules

| Area | Result |
|------|--------|
| REFUND semantics | **UNCHANGED** |
| RETURN semantics | **UNCHANGED** |
| `settled_amount` logic | **UNCHANGED** |
| Step 2.7B cap / 2.7C UI | **UNCHANGED** |
| Refund regression test | **PASS** — test P (no REFUND on partial return) |

## 11. Test Integrity

**Suite:** `test/customer_returns_database_integrity_phase_c_step_2_8b_test.dart` — **29 tests**, real Drift/SQLite (`AppDatabase.test`, in-memory, temp file, raw `sqlite3`).

| Requirement | Covered | Notes |
|-------------|---------|-------|
| Schema 33 | A | |
| Index exists | B | |
| First header insert | C | via `processPartialReturn` |
| Second batch reuses header | D | |
| Total accumulation | E | |
| NULL headers | F | |
| Duplicate insert ignored | G | accepts `ignoredId == 0 \|\| ignoredId == firstId` (Drift semantics) |
| Concurrent upsert | H | raw SQL, two connections |
| INSERT OR IGNORE recovery | I | DAO upsert after pre-seeded header |
| returnAllRemaining reuse | J | |
| Partial → full | K | |
| Clean full return | L | |
| Cash invoice | M | |
| Read path | N | |
| Refund regression | P | |
| Migration 32→33 | Q | |
| NULL migration | R | |
| Duplicate migration gate | S | async migration trigger |
| Rollback | Q rollback | forced credit failure |
| Stock / sale_item_returns / RETURN | carryover J–N (2.6 labels) | sequential integration |

Tests use production services/DAOs; no mocks bypassing header upsert on integration paths.

**NON-BLOCKING:** Duplicate letter prefixes (J/K/L/M/N reused from 2.6 carryover) — cosmetic only; all 29 tests pass.

## 12. Validation

Independent re-run (`-j 1` where noted):

| Check | Result |
|-------|--------|
| Focused Step 2.8B | **29/29 PASS** |
| Customer Returns Phase C (11 files) | **203/203 PASS** |
| Supplier regression (11 files) | **131/131 PASS** |
| `flutter analyze` (scoped production files) | **PASS** — 0 issues |
| `dart format --set-exit-if-changed` | **PASS** — 0 changed |
| `flutter build windows --debug` | **PASS** |

## 13. Documentation

`docs/customer_returns_phase_c_step_2_8b_database_integrity.md` reviewed:

| Check | Result |
|-------|--------|
| Matches implementation | **PASS** |
| States local active DB audited, zero duplicates | **PASS** |
| Does **not** claim remote production audited | **PASS** |
| Deferred work listed | **PASS** |

## 14. Findings

| ID | Classification | Finding |
|----|----------------|---------|
| F-01 | **NON-BLOCKING** | Test H validates concurrent upsert via raw SQLite SQL mirroring DAO logic, not dual-connection Drift `upsertPartialReturnDocumentHeader()`. Acceptable given `SQLITE_BUSY` on full partial-return concurrency; integration paths covered sequentially. |
| F-02 | **NON-BLOCKING** | Test suite reuses letter labels (J/K/L/M/N) from 2.6 carryover tests — naming only. |
| F-03 | **INFORMATIONAL** | `onCreate` explicitly creates partial UNIQUE index (in addition to v33 migration) so fresh/test databases match upgraded stores. |
| F-04 | **INFORMATIONAL** | Untracked prior-phase docs present in working tree; not part of Step 2.8B tracked diff. |
| F-05 | **INFORMATIONAL** | Test G tolerates Drift `insertOrIgnore` returning `0` or pre-existing row ID on conflict. |

**BLOCKER:** none  
**REQUIRES HARDENING:** none

## 15. Final Decision

**GO TO FINAL AUDIT**