# Customer Returns Phase C — Step 2.8B Final Audit

**Date:** 2026-09-24  
**Auditor:** Independent read-only final certification  
**Review Pass:** GO TO FINAL AUDIT (0 blockers, 0 requires hardening)  
**Mode:** Read-only — no production code, tests, migrations, or implementation docs modified

---

## 1. Final Certification

Step 2.8B — Database Integrity Hardening — is **CERTIFIED FOR COMMIT**.

Independent re-verification confirms schema 33, partial UNIQUE index, conflict-aware header upsert, migration safety, transaction atomicity preservation, full-return compatibility, NULL semantics, financial architecture isolation, test integrity, regression cleanliness, and static validation. Zero blockers and zero items requiring hardening.

---

## 2. Actual Baseline

| Check | Result |
|-------|--------|
| `git rev-parse HEAD` | `1b52d9e1c7c7f13e3958433710e5957e6d91954f` |
| `git log -1 --oneline` | `1b52d9e feat(customer-returns): harden aggregate refund concurrency` |
| Branch | `main` @ `1b52d9e`, tracking `origin/main` (Step 2.8A committed/pushed) |
| Step 2.8B state | **Uncommitted** working-tree changes only |
| Current schema (working tree) | **33** |

**Tracked modifications (uncommitted):**

- `lib/core/database/app_database.dart`
- `lib/core/database/daos/returns_dao.dart`
- `lib/core/database/tables/customer_returns_table.dart`
- `test/customer_return_settlement_state_phase_c_step_2_7a_test.dart` (schema expectation 32→33)

**Untracked Step 2.8B artifacts:**

- `test/customer_returns_database_integrity_phase_c_step_2_8b_test.dart`
- `docs/customer_returns_phase_c_step_2_8b_database_integrity.md`
- `docs/customer_returns_phase_c_step_2_8b_review_pass.md`
- `docs/customer_returns_phase_c_step_2_8b_final_audit.md` (this document)

Other untracked prior-phase docs/tools present; not part of Step 2.8B tracked diff.

---

## 3. Scope

**`git diff --stat` (tracked):** 4 files, +83 / −10 lines

| File | Verdict |
|------|---------|
| `lib/core/database/app_database.dart` | **In scope** — schema 33, onCreate index, v33 migration |
| `lib/core/database/daos/returns_dao.dart` | **In scope** — `upsertPartialReturnDocumentHeader()` only |
| `lib/core/database/tables/customer_returns_table.dart` | **In scope** — Drift partial UNIQUE index declaration |
| `test/customer_return_settlement_state_phase_c_step_2_7a_test.dart` | **In scope** — schema expectation bump |

**No unrelated production changes** in tracked diff. `git diff 1b52d9e` shows zero changes under `lib/core/services/`, `lib/features/`, `CustomerRefundSettlementService`, `CustomerAccountsDao`, and `partial_return_service.dart`.

**SCOPE: PASS**

---

## 4. Schema 33

| Requirement | Result |
|-------------|--------|
| `schemaVersion == 33` | **PASS** (`app_database.dart:147`) |
| Migration block `from < 33` only | **PASS** |
| Duplicate pre-flight on non-NULL `original_invoice_id` groups | **PASS** — throws `StateError` with group count |
| Reject duplicates before index creation | **PASS** |
| Partial UNIQUE index creation | **PASS** |
| No automatic data merge/cleanup | **PASS** |
| Preserve existing rows, NULL headers, `settled_amount`, FKs | **PASS** — no UPDATE/DELETE in v33 block |
| `original_invoice_id` remains nullable | **PASS** — no column DDL |
| No unrelated schema changes in v33 | **PASS** |
| Fresh install (`onCreate`) creates same index | **PASS** — explicit `CREATE UNIQUE INDEX … WHERE … IS NOT NULL` after `createAll()` |

**SCHEMA_33: PASS**

---

## 5. Unique Index

Verified identical SQL in onCreate, migration v33, and Drift table declaration:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_customer_returns_original_invoice
ON customer_returns(original_invoice_id)
WHERE original_invoice_id IS NOT NULL;
```

| Property | Result |
|----------|--------|
| Index name stable | **PASS** — `uq_customer_returns_original_invoice` |
| Non-NULL invoice IDs unique | **PASS** — partial UNIQUE + tests G, F-dup |
| Multiple NULL allowed | **PASS** — tests F, R |
| No full-table UNIQUE replacing partial | **PASS** |
| Drift declaration matches runtime | **PASS** |

**UNIQUE_INDEX: PASS**

---

## 6. Conflict-Aware Upsert

`ReturnsDao.upsertPartialReturnDocumentHeader()` audited (`returns_dao.dart:123-177`):

| Path | Behavior | Result |
|------|----------|--------|
| Existing header | SELECT → `_incrementCustomerReturnHeaderTotal` → return ID | **PASS** |
| Missing header | `INSERT OR IGNORE` (`InsertMode.insertOrIgnore`) | **PASS** |
| Successful insert | `insertedId != 0` → return ID | **PASS** |
| Conflict | re-SELECT → increment total → return existing ID | **PASS** |
| Race-prone plain INSERT | **Removed** | **PASS** |
| `insertOnConflictUpdate` | **Not used** | **PASS** |
| Total accumulation | Re-read header; `header.total + batchGoodsTotal` | **PASS** |
| Nested transaction in DAO | **None** | **PASS** |
| Invalid ID on ignored insert | Guarded — conflict path re-SELECTs before return | **PASS** |

**CONFLICT_UPSERT: PASS**

---

## 7. Concurrency

Test H (`concurrent header upserts share one customer_returns row`) uses two raw `sqlite3` connections on one database file with SQL mirroring the DAO upsert pattern (`INSERT OR IGNORE` → re-SELECT → increment). Asserts one header, combined total 50 (20+30), no UNIQUE exception.

| Check | Result |
|-------|--------|
| Two connections racing on same invoice | **PASS** |
| Exactly one header | **PASS** |
| Combined total | **PASS** |
| UNIQUE exception surfaced | **PASS** — none |
| Broad SQLITE_BUSY retry in production | **PASS** — not introduced |

**Assessment:** Test H does not invoke dual-connection Drift calls to `upsertPartialReturnDocumentHeader()` because full `processPartialReturn` concurrency caused `SQLITE_BUSY` on downstream tables during implementation. The raw-SQL test validates the header upsert invariant; sequential integration tests cover stock, `sale_item_returns`, and RETURN posting.

**Classification:** **NON-BLOCKING** test-scope limitation — acceptable for Step 2.8B.

**CONCURRENCY: PASS**

---

## 8. Transaction Atomicity

`PartialReturnService.processPartialReturn()` wraps steps 1–9 in `_db.transaction()` (`partial_return_service.dart:180`), including header upsert at line 303, items, stock, audit, RETURN posting, and status refresh.

| Check | Result |
|-------|--------|
| Upsert inside caller transaction | **PASS** |
| No nested DAO transaction | **PASS** |
| Rollback on forced credit failure | **PASS** — test `Q) rollback removes customer_returns and sale_item_returns on failure` |

**TRANSACTION_ATOMICITY: PASS**

---

## 9. Full Return Compatibility

`returnFullSaleInvoice()` diff: **unchanged** in Step 2.8B. Duplicate guard at `dup != null` remains (`returns_dao.dart:326-331`).

| Scenario | Test | Result |
|----------|------|--------|
| Clean full return → one header | L | **PASS** |
| Partial → full → same header | K | **PASS** |
| returnAllRemaining reuse | J | **PASS** |
| No duplicate when fully returned | S-full | **PASS** |
| Repeated full return guard | Existing `dup != null` throw | **PASS** |

**FULL_RETURN: PASS**

---

## 10. NULL Semantics

| Check | Result |
|-------|--------|
| Column nullable in schema | **PASS** |
| Multiple NULL headers insertable | **PASS** — test F |
| Migration preserves NULL headers | **PASS** — test R |
| Partial index excludes NULL | **PASS** |
| Manual/quick return paths unchanged | **PASS** — no production changes outside upsert/migration |

**NULL_SEMANTICS: PASS**

---

## 11. Financial Architecture

Verified **zero diff** since `1b52d9e` for refund/settlement/ledger modules. Step 2.8B changes are limited to document-integrity protection (partial UNIQUE index + header upsert).

| Area | Result |
|------|--------|
| `CustomerRefundSettlementService` | **UNCHANGED** |
| `CustomerAccountsDao` aggregate refund guard | **UNCHANGED** |
| Step 2.7A `settled_amount` | **UNCHANGED** |
| Step 2.7B per-return cap | **UNCHANGED** |
| Step 2.7C UI | **UNCHANGED** |
| `customer_transactions` REFUND/RETURN semantics | **UNCHANGED** |
| `FinancialLedgerRepository` / Cash Ledger | **UNCHANGED** |
| Refund regression | **PASS** — test P |

**FINANCIAL_ARCHITECTURE: PASS**

---

## 12. Migration Safety

| Scenario | Result |
|----------|--------|
| Clean schema 32 → 33 | **PASS** — test Q |
| Legitimate NULL headers preserved | **PASS** — test R |
| Duplicate fixture rejected before index | **PASS** — test S throws `StateError` |
| No automatic merge/delete of duplicates | **PASS** — pre-flight gate only |
| `settled_amount` preserved | **PASS** — fixture in Q |

**MIGRATION: PASS**

---

## 13. Test Integrity

**Suite:** `test/customer_returns_database_integrity_phase_c_step_2_8b_test.dart` — **29 tests**

Real Drift/SQLite (`AppDatabase.test`, in-memory, temp file, raw `sqlite3`). Production services/DAOs on integration paths; no mocks bypassing header upsert.

| Area | Covered |
|------|---------|
| Schema 33 | A |
| Index exists | B |
| First header / items | C, B-skip |
| Second batch reuse | D, D-items |
| Total accumulation | E |
| NULL headers | F |
| Duplicate insert ignored | G |
| Concurrent upsert pattern | H |
| DAO conflict recovery | I |
| returnAllRemaining | J |
| Partial → full | K |
| Clean full return | L |
| 2.6 carryover regression | J/K/L/M/N (stock, RETURN, read path) |
| Cash invoice | M |
| Read path | N |
| Refund regression | P |
| Migration 32→33 | Q |
| NULL migration | R |
| Duplicate migration gate | S |
| Rollback | Q rollback |
| Full-return no duplicate | S-full, R-batches |

**Cosmetic note (informational):** Duplicate letter prefixes J/K/L/M/N from 2.6 carryover — naming only; all tests pass.

**TEST_INTEGRITY: PASS**

---

## 14. Regression

Independent re-run during Final Audit (`-j 1`):

| Suite | Result |
|-------|--------|
| Focused Step 2.8B | **29/29 PASS** |
| Customer Returns Phase C (11 files) | **203/203 PASS** |
| Supplier regression (11 supplier_*.dart files) | **131/131 PASS** |

Customer regression files: step_1, step_2_6, refund 2/2/2.3/2.4/settlement, 2.7a/2.7b/2.7c, 2.8a, 2.8b.

**REGRESSION: PASS**

---

## 15. Static Validation

| Check | Result |
|-------|--------|
| `flutter analyze` (app_database, returns_dao, customer_returns_table) | **PASS** — 0 issues |
| `dart format --set-exit-if-changed` (scoped production + Step 2.8B tests) | **PASS** — 0 changed |
| `flutter build windows --debug` | **PASS** — `build\windows\x64\runner\Debug\lez_pos.exe` |
| Schema | **33** |

**ANALYZER: PASS | FORMAT: PASS | WINDOWS_BUILD: PASS**

---

## 16. Documentation

Reviewed (read-only):

- `docs/customer_returns_phase_c_step_2_8b_database_integrity.md`
- `docs/customer_returns_phase_c_step_2_8b_review_pass.md`

| Check | Result |
|-------|--------|
| Local active DB identified; zero local duplicates stated | **PASS** |
| Does not claim remote production audited | **PASS** |
| Migration behavior accurate | **PASS** |
| Conflict-aware upsert accurate | **PASS** |
| Deferred work accurate | **PASS** |

**DOCUMENTATION: PASS**

---

## 17. Deferred Work

Confirmed outside Step 2.8B scope:

- Remote production duplicate audit and remediation
- Broad SQLITE_BUSY retry policy
- `PosSaleService.processReturn` removal
- Refund idempotency
- `CustomerReturnService` refactor
- Historical backfill / duplicate cleanup
- RETURN reference redesign

---

## 18. Findings

| ID | Classification | Finding |
|----|----------------|---------|
| F-01 | **NON-BLOCKING** | Test H validates concurrent header upsert via raw SQLite SQL mirroring DAO logic, not dual-connection Drift `upsertPartialReturnDocumentHeader()`. Acceptable given SQLITE_BUSY on full partial-return concurrency; integration paths covered sequentially. |
| F-02 | **NON-BLOCKING** | Test suite reuses letter labels (J/K/L/M/N) from 2.6 carryover — cosmetic naming only. |
| F-03 | **INFORMATIONAL** | `onCreate` explicitly creates partial UNIQUE index (in addition to v33 migration) so fresh/test databases match upgraded stores. |
| F-04 | **INFORMATIONAL** | Untracked prior-phase docs and `tool/_write_2_7c_test.dart` in working tree; not part of Step 2.8B diff. |
| F-05 | **INFORMATIONAL** | Test G tolerates Drift `insertOrIgnore` returning `0` or pre-existing row ID on conflict. |

**BLOCKERS:** 0  
**REQUIRES HARDENING:** 0

---

## 19. Final Decision

All certification criteria met. Step 2.8B is **CERTIFIED FOR COMMIT**.

No commit, push, or stage performed during Final Audit.

---

HEAD:
1b52d9e1c7c7f13e3958433710e5957e6d91954f

SCHEMA:
33

BLOCKERS:
0

REQUIRES_HARDENING:
0

NON_BLOCKING:
2

INFORMATIONAL:
3

FOCUSED_TESTS:
29/29 PASS

CUSTOMER_REGRESSION:
203/203 PASS

SUPPLIER_REGRESSION:
131/131 PASS

ANALYZER:
PASS

FORMAT:
PASS

WINDOWS_BUILD:
PASS

SCHEMA_33:
PASS

UNIQUE_INDEX:
PASS

NULL_SEMANTICS:
PASS

CONFLICT_UPSERT:
PASS

CONCURRENCY:
PASS

TRANSACTION_ATOMICITY:
PASS

FINANCIAL_ARCHITECTURE:
PASS

MIGRATION:
PASS

TEST_INTEGRITY:
PASS

SCOPE:
PASS

DOCUMENTATION:
PASS

FINAL DECISION:

CERTIFIED FOR COMMIT