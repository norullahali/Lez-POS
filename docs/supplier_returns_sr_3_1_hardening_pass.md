# Supplier Returns SR.3.1 — Hardening Pass

## Executive Summary

Hardening pass closed all 7 REQUIRES HARDENING findings from the SR.3.1 Review Pass. Changes are limited to SR.3.1 lifecycle, async safety, dialog guards, and regression tests. **No SR.2 posting behavior was modified.** Save button remains disabled. Schema remains 31.

**Final Decision: GO TO FINAL AUDIT**

**Readiness Score: 96 / 100**

---

## Hardening Scope

Modified production files:
- lib/features/returns/providers/supplier_return_draft_provider.dart
- lib/features/returns/screens/widgets/create_supplier_return_dialog.dart
- lib/features/returns/screens/supplier_returns_screen.dart
- lib/features/returns/repositories/supplier_return_read_repository.dart

Modified tests:
- test/supplier_return_draft_sr_3_1_test.dart

No SR.2 service/DAO changes. No schema changes. No posting integration.

---

## R-01 Duplicate Dialog Fix — CLOSED

**Implementation:** `_createDialogOpen` guard on `SupplierReturnsScreen` with button disabled while dialog is open. `whenComplete` clears guard on any dismiss path.

**Test:** `R-01 rapid taps open only one dialog`

---

## R-02 Barrier Dismiss Reset Fix — CLOSED

**Implementation:** `showCreateSupplierReturnDialog` now:
1. Calls `reset()` on open (clean session)
2. Returns `showDialog(...).whenComplete(() => reset())` for all dismiss paths

Explicit close handlers only call `Navigator.pop()`; reset centralized in `whenComplete`.

**Test:** `R-08 barrier dismiss resets draft on reopen`

---

## R-04 Stale Async Completion Fix — CLOSED

**Implementation:** Request-generation tokens in `SupplierReturnDraftNotifier`:
- `_loadPurchasesGeneration` for `loadPurchases`
- `_loadLinesGeneration` for `selectPurchase`

Each async completion checks generation before mutating state. Stale results ignored.

**Tests:** `B wins when A completes after B`, `stale A error does not overwrite active B selection`

---

## R-05 Back-to-Selector Invalidation Fix — CLOSED

**Implementation:** `backToPurchaseSelection()` calls `_invalidateLineLoads()` (increments generation), clears lines, sets `loadingLines: false`, clears errors.

**Test:** `backToPurchaseSelection ignores late A completion`

---

## R-06 Same-Product Test Strengthening — CLOSED

**Test:** `line quantities keyed by purchaseItemId not productId` — invoice with two lines sharing same productId; qty on line 101 does not affect line 102.

---

## R-07 Async Race Test — CLOSED

**Implementation:** `_ControllableReadRepository` with `Completer`-controlled `loadDraftLines`.

Deterministic tests (no arbitrary delays):
- A then B, B completes first, A completes after — B remains
- A loading, back to selector, A completes — state stays clean
- A fails after B active — no stale error on B

---

## R-08 Barrier Dismiss Test — CLOSED

Widget test via `_DialogTestHost` + `_StatefulReadRepository`:
open → select purchase → set qty → barrier tap → assert reset → reopen → assert clean.

---

## R-03 Dialog Opener Cleanup — CLEANED

Removed unnecessary `async` from dialog entry. Renamed to `_openCreateSupplierReturnDialog()` (sync void).

---

## Draft Lifecycle Contract

| Event | State |
|-------|-------|
| Dialog open | `reset()` then load purchases |
| Dialog close (any path) | `reset()` via whenComplete |
| Purchase select | Clear lines, increment line generation, load |
| Back to selector | Invalidate generation, clear lines/loading/errors |
| Reopen | Always clean initial state |

---

## Async Request Contract

Only the latest generation may update:
- `purchases` / `loadingPurchases` / purchase load errors
- `lines` / `loadingLines` / line load errors

Obsolete success and failure results are silently discarded.

---

## SR.2 Isolation Certification

Git diff confirms no changes to:
- SupplierReturnService.postPurchaseLinkedReturn()
- ReturnsDao.persistSupplierReturn()
- SupplierAccountsDao.recordReturnInTransaction()
- ReturnsDao.getReturnableQuantityForPurchaseItem()
- StockGuard / FinancialLedgerRepository

Certified regression: 26/26 PASS

---

## Financial Side-Effect Certification

Unchanged from SR.3.1 foundation:
- SupplierReturn rows: 0
- Stock changes: 0
- Supplier accounting: 0
- Cash Ledger: 0
- SupplierReturnService: NOT CALLED

---

## Schema Certification

31 → 31. No migration.

---

## Test Results

| Suite | Result |
|-------|--------|
| SR.1 | 11 / 11 PASS |
| SR.2 | 11 / 11 PASS |
| Hardening | 4 / 4 PASS |
| SR.3.1 | 18 / 18 PASS |
| **Total** | **44 / 44 PASS** |

SR.3.1 test count increased from 12 to 18 (+6 hardening tests).

---

## Validation Results

| Check | Result |
|-------|--------|
| dart format | PASS |
| flutter analyze | 104 pre-existing issues |
| flutter build windows --debug | PASS |

---

## Remaining Findings

| ID | Item | Status |
|----|------|--------|
| H-01 | Uncontrolled reason/notes TextFields | NON-BLOCKING (deferred) |
| — | N+1 returnable reads | ACCEPTED FOR SR.3.1 |
| — | DRAFT purchase eligibility | ACCEPTED |

**BLOCKERS: 0**
**REQUIRES HARDENING: 0**
**NON-BLOCKING: 1**
**DEFERRED SR.3.2+: 1** (batch read API if needed)

---

## Readiness Score

**96 / 100**

All review hardening items closed. Minor non-blocking UX items remain.

---

## Final Decision

**GO TO FINAL AUDIT**

Do NOT proceed to SR.3.2 until Final Audit completes.