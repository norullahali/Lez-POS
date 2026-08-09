# Supplier Returns SR.3.1 — Review Pass

## Executive Summary

Strict read-only review of Phase SR.3.1 (UI Workflow & Read Contract Foundation). **No production code was modified during this pass.**

SR.3.1 correctly implements a read-only purchase-linked draft workflow with zero write-side effects. Scope certification passes. Certified SR.1/SR.2 paths are untouched. All 38 regression tests pass. Windows debug build succeeds.

**Two lifecycle/async gaps** were identified that must be hardened before SR.3.2 posting integration: (1) stale async completion in `selectPurchase`, (2) barrier-dismiss without draft reset. Neither causes financial side effects in SR.3.1, but both can corrupt draft state UX.

**Final Decision: GO TO HARDENING**

**Readiness Score: 89 / 100**

---

## Scope Certification

Searched SR.3.1 production path (`lib/features/returns/models/`, `repositories/`, `providers/`, `screens/widgets/create_supplier_return_dialog.dart`, modified `supplier_returns_screen.dart`) for:

| Pattern | Found in SR.3.1 path? |
|---------|----------------------|
| insert / update / delete | NO |
| transaction | NO |
| StockGuard / StockLedger | NO |
| supplier accounting mutation | NO |
| Cash Ledger mutation | NO |
| SupplierReturnService.postPurchaseLinkedReturn | NO |
| ReturnsDao.saveSupplierReturn | NO |
| ReturnsDao.persistSupplierReturn | NO |

**Result: PASS — zero write-side effects in SR.3.1 production path.**

---

## UI Entry-Point Review

**File:** `supplier_returns_screen.dart`

| Check | Result |
|-------|--------|
| Placeholder SnackBar removed | PASS |
| Opens `showCreateSupplierReturnDialog` | PASS |
| Single workflow entry | PASS |

**Findings:**

| ID | Finding | Classification |
|----|---------|----------------|
| R-01 | No guard against opening multiple dialogs if button pressed rapidly; both share global `supplierReturnDraftProvider` | REQUIRES HARDENING |
| R-02 | `barrierDismissible: true` but `reset()` only on explicit close (X / إغلاق); barrier tap leaves stale draft in global provider | REQUIRES HARDENING |
| R-03 | `_showSupplierReturnDialog` is `async` but does not await dialog; harmless but unnecessary | NON-BLOCKING |

---

## Purchase Selector Review

**File:** `create_supplier_return_dialog.dart` → `_PurchaseSelector`

| Check | Result |
|-------|--------|
| Invoice number displayed | PASS (`displayInvoiceNumber`) |
| Supplier displayed | PASS |
| Date displayed | PASS (`DateFormat yyyy/MM/dd`) |
| Total displayed | PASS (`toStringAsFixed(2)`) |
| Search is in-memory only | PASS (no DB per keystroke) |
| Empty purchase list UX | PASS (Arabic message) |
| Empty search results UX | PASS |

**Search behavior:** `filteredPurchases` uses `toLowerCase()` on query, invoice number, and supplier name. Case-safe for Latin invoice numbers. Arabic supplier names are matched literally (no Arabic case folding) — acceptable for SR.3.1.

---

## Purchase Eligibility Review

**Source:** `PurchaseStatus` enum in `movement_types.dart`:
- `DRAFT` (`DRAFT`)
- `CONFIRMED` (`CONFIRMED`)
- `cancelled` (`CANCELLED`)

**Repository rule:** exclude only `CANCELLED`; require `supplierId != null` and supplier row exists.

Verified against source — no other void/terminal status exists in schema.

| Check | Result |
|-------|--------|
| CANCELLED excluded | PASS |
| Missing supplier excluded | PASS |
| DRAFT invoices eligible | ACCEPTED (per SR.3.1 spec: no speculative restrictions beyond cancelled) |

DRAFT purchases may appear in selector. SR.2 posting validation remains authoritative at post time. Optional CONFIRMED-only filter deferred to hardening if product owner prefers.

---

## Supplier Consistency

| Check | Result |
|-------|--------|
| Supplier derived from selected purchase | PASS |
| No independent supplier picker | PASS |
| Supplier shown in lines step header | PASS |
| Purchase change clears lines (`backToPurchaseSelection`) | PASS |

**Result: PASS**

---

## Purchase Item Identity

| Check | Result |
|-------|--------|
| Draft line keyed by `purchaseItemId` | PASS |
| `setLineQuantity` uses `purchaseItemId` | PASS |
| TextEditingController map keyed by `purchaseItemId` | PASS |
| No Map keyed by `productId` only | PASS |

Lines list preserves one entry per purchase item. Same product on two lines would remain separate (repository iterates `getItemsForInvoice` by item id).

**Result: PASS**

---

## Returnable Quantity Authority

**Delegation chain:**
```
loadDraftLines → ReturnsDao.getReturnableQuantityForPurchaseItem(item.id)
```

SR.1 canonical math: `max(0, purchased - SUM(linked returns))` with per-`purchaseItemId` SQL.

**Presentation derivation:**
```dart
alreadyReturnedQty = purchased - returnable  // clamped >= 0
```

Safe under SR.1 clamp semantics (when returns exceed purchased, returnable=0, alreadyReturned=purchased).

**Result: PASS — UI does not recreate canonical math; only presentation subtraction.**

---

## N+1 Read Assessment

Per invoice with N items:
- 1 × `getItemsForInvoice`
- N × `getReturnableQuantityForPurchaseItem`
- N × product name lookup

Plus eligibility scan: 1 × `getAllInvoices` + M × `getSupplierById`.

**Classification: ACCEPTED FOR SR.3.1**

Typical purchase invoices have bounded line counts. Batch API deferred unless profiling shows pain.

---

## Draft State Ownership

**Provider:** global `NotifierProvider<SupplierReturnDraftNotifier>` — not auto-disposed with dialog.

| Check | Result |
|-------|--------|
| `reset()` returns to initial state | PASS |
| Purchase replacement clears lines in `selectPurchase` | PASS |
| Quantity updates immutable line copy | PASS |
| Error transitions use Arabic messages | PASS |
| No SQLite writes during edit | PASS |

---

## Async Race Review

**Critical scenario audited:** User selects Purchase A, then Purchase B (or navigates back) while A load is in-flight.

**Current `selectPurchase` implementation:**
```dart
final lines = await _repo.loadDraftLines(purchase.purchaseInvoiceId);
state = state.copyWith(lines: lines, loadingLines: false);
// NO guard: stale completion can overwrite newer selection
```

**Additional scenario:** User selects A, taps "تغيير الفاتورة" during load — `backToPurchaseSelection` does not cancel in-flight load; stale A lines can land after user returned to selector or selected B.

| ID | Finding | Classification |
|----|---------|----------------|
| R-04 | Stale `loadDraftLines` completion can overwrite lines for a newer purchase selection | REQUIRES HARDENING |
| R-05 | `backToPurchaseSelection` does not invalidate in-flight load; `loadingLines` not cleared on back | REQUIRES HARDENING |

Not a financial BLOCKER in SR.3.1 (no posting), but **must be fixed before SR.3.2** to prevent wrong-line draft submission.

---

## Quantity Validation

**File:** `supplier_return_draft_models.dart` → `validateDraftLineQuantity()`

| Rule | Implemented |
|------|-------------|
| qty >= 0 | YES |
| qty <= returnableQty (+ epsilon) | YES |
| zero = unselected | YES (accepted, no error) |
| empty input → 0 | YES (`double.tryParse(v) ?? 0`) |
| decimal quantities | YES (matches `double` purchase qty domain) |

Arabic error strings verified in source (UTF-8 intact).

**Result: PASS**

---

## canProceed Review

```dart
bool get canProceed => hasReturnableLines && hasSelectedQty && !hasLineErrors;
```

| Condition | Covered |
|-----------|---------|
| At least one line with qty > 0 | YES (`hasSelectedQty`) |
| All selected quantities valid | YES (`!hasLineErrors`) |
| Returnable lines exist | YES (`hasReturnableLines`) |
| Explicit selectedPurchase check | Implicit (lines only loaded after selection) |

Zero-returnable invoice: `hasReturnableLines` false → `canProceed` false. Correct.

Save button is disabled regardless (`onPressed: null`).

**Result: PASS**

---

## Draft Total Review

```dart
double get draftTotal => lines.fold(0.0, (sum, l) => sum + l.lineDraftTotal);
// lineDraftTotal = selectedReturnQty * unitCost
```

- Presentation-only display in dialog footer
- Not passed to any DAO, service, or storage path
- Uses `double` — consistent with existing purchase cost fields

Minor float precision inherent to project conventions — not a blocker.

**Result: PASS**

---

## Zero-Returnable UX

When all lines have `returnableQty == 0`:
- Warning banner in Arabic displayed
- Line inputs disabled (`enabled: line.returnableQty > 0`)
- `canProceed` false
- Save button disabled
- "تغيير الفاتورة" available

**Result: PASS**

---

## Loading / Error UX

| State | Handling |
|-------|----------|
| Loading purchases | Spinner |
| Loading lines | Spinner |
| Read failure | Arabic: تعذر تحميل... |
| Empty purchases | Arabic empty message |
| Zero returnable | Arabic warning banner |

Exceptions caught with `catch (_)` — raw SQLite/Drift/stack traces not shown.

**Result: PASS**

---

## Save Button Safety

```dart
FilledButton.icon(onPressed: null, label: Text('حفظ المرتجع'))
```

Callback chain searched — no path to SupplierReturnService, ReturnsDao write methods, StockGuard, SupplierAccountsDao, or Cash Ledger.

**Result: PASS**

---

## Legacy DAO Isolation

No reference to `ReturnsDao.saveSupplierReturn()` in SR.3.1 files.

**Result: PASS**

---

## SR.2 Isolation

Git diff confirms SR.3.1 modified only `supplier_returns_screen.dart` plus new SR.3.1 files. No changes to:

- `SupplierReturnService.postPurchaseLinkedReturn()`
- `ReturnsDao.persistSupplierReturn()`
- `SupplierAccountsDao.recordReturnInTransaction()`
- SR.1 `getReturnableQuantityForPurchaseItem()`

**Result: PASS**

---

## Riverpod Rebuild Assessment

- Dialog root watches full `supplierReturnDraftProvider` — rebuilds on search keystrokes and qty changes
- Scope limited to dialog subtree (~960×720)
- `_LinesTable` uses `ref.read` for mutations

**Classification: ACCEPTABLE** — no app-wide rebuild; dialog-scoped only.

---

## Desktop / RTL UX

| Check | Result |
|-------|--------|
| RTL textDirection on Arabic widgets | PASS |
| 960×720 constrained dialog | PASS |
| ScrollView for many lines | PASS |
| Long names wrap in Expanded columns | PASS |
| Numeric keyboard + decimal input | PASS |
| Disabled save visible with tooltip | PASS |

Reason/notes TextFields are uncontrolled (no `controller`/`initialValue`) — if draft reopened without reset, fields appear empty while state may hold prior values. Minor — tied to R-02.

**Classification: ACCEPTABLE**

---

## Test Quality Audit

**Count verified: 12 tests in `supplier_return_draft_sr_3_1_test.dart`**

| ID | Test | Quality |
|----|------|---------|
| A | Widget opens dialog | PASS (mock repo avoids spinner timeout) |
| B | Eligible purchases include invoice | PASS (repository level) |
| C/D | Items + SR.1 returnable qty | PASS (compares to DAO) |
| E | Same-product isolation | WEAK — uses different products; verifies line isolation via purchaseItemId indirectly |
| F | Previous returns reduce qty | PASS |
| G | Excessive qty rejected | PASS |
| H | Purchase change clears draft | PASS (via backToPurchaseSelection, not re-select) |
| I | Zero returnable | PASS |
| J | Zero side effects | PASS |
| — | validateDraftLineQuantity | PASS |
| — | draft total | PASS |

| ID | Finding | Classification |
|----|---------|----------------|
| R-06 | Test E does not seed same `productId` on two purchase lines | REQUIRES HARDENING |
| R-07 | No test for async stale-result race (R-04) | REQUIRES HARDENING |
| R-08 | No test for barrier-dismiss state persistence (R-02) | REQUIRES HARDENING |
| R-09 | Test H covers back navigation, not A→B rapid re-select | NON-BLOCKING |

Tests are not brittle pixel tests. Side-effect test J is substantive.

---

## Financial Side-Effect Certification

Confirmed via implementation audit + test J:

| Metric | Delta |
|--------|-------|
| SupplierReturn rows | 0 |
| SupplierReturnItem rows | 0 |
| RETURN_OUT events | 0 |
| Stock quantity | 0 |
| Supplier transaction rows | 0 |
| Supplier balance | 0 |
| Cash Ledger events | 0 |

**Result: PASS**

---

## Schema Certification

`AppDatabase.schemaVersion => 31`. No migration added in SR.3.1.

**Result: PASS (31 → 31)**

---

## Code Hygiene Findings

| ID | Finding | Classification |
|----|---------|----------------|
| H-01 | `reason` / `notes` fields captured but not displayed on reopen (uncontrolled TextFields) | NON-BLOCKING |
| H-02 | `getPurchaseOption()` in repository unused | NON-BLOCKING |
| H-03 | Global NotifierProvider for dialog-scoped draft (works with reset, fragile without) | ACCEPTED |
| H-04 | No debug prints / TODO / FIXME in SR.3.1 files | PASS |
| H-05 | No DAO leakage into widgets | PASS |
| H-06 | No hardcoded technical IDs exposed in UI | PASS |

---

## Regression Results

| Suite | Result |
|-------|--------|
| SR.1 (`supplier_return_returnable_quantity_test.dart`) | 11 / 11 PASS |
| SR.2 (`supplier_return_posting_service_test.dart`) | 11 / 11 PASS |
| Hardening (`supplier_return_hardening_test.dart`) | 4 / 4 PASS |
| SR.3.1 (`supplier_return_draft_sr_3_1_test.dart`) | 12 / 12 PASS |
| **Total** | **38 / 38 PASS** |
| flutter analyze | 104 issues (pre-existing; no SR.3.1 errors) |
| flutter build windows --debug | PASS |

---

## Findings Table

| ID | Section | Finding | Classification |
|----|---------|---------|----------------|
| R-01 | UI Entry | Duplicate dialog open not guarded | REQUIRES HARDENING |
| R-02 | UI Entry | Barrier dismiss skips reset() | REQUIRES HARDENING |
| R-03 | UI Entry | Unnecessary async on dialog opener | NON-BLOCKING |
| R-04 | Async Race | Stale loadDraftLines overwrites newer purchase | REQUIRES HARDENING |
| R-05 | Async Race | backToPurchaseSelection does not cancel in-flight load | REQUIRES HARDENING |
| R-06 | Tests | Test E weak for same-product scenario | REQUIRES HARDENING |
| R-07 | Tests | No async race regression test | REQUIRES HARDENING |
| R-08 | Tests | No barrier-dismiss lifecycle test | REQUIRES HARDENING |
| R-09 | Tests | Test H does not cover A→B re-select | NON-BLOCKING |
| H-01 | Hygiene | Uncontrolled reason/notes fields | NON-BLOCKING |
| H-02 | Hygiene | Unused getPurchaseOption() | NON-BLOCKING |
| — | Eligibility | DRAFT invoices eligible | ACCEPTED |
| — | N+1 reads | Per-item returnable query | ACCEPTED FOR SR.3.1 |
| — | Rebuilds | Dialog-scoped provider watch | ACCEPTABLE |

**BLOCKERS: 0**
**REQUIRES HARDENING: 7**
**NON-BLOCKING: 4**
**ACCEPTED: 3**
**DEFERRED SR.3.2+: 1** (batch returnable read API if profiling warrants)

---

## Hardening Recommendations

1. **Request token / invoiceId guard** in `selectPurchase` and `loadPurchases` — ignore stale async completions.
2. **Reset on dialog dismiss** — `showDialog(...).then((_) => reset())` or `PopScope`.
3. **Cancel or ignore in-flight load** when `backToPurchaseSelection()` is called.
4. **Prevent duplicate dialog** — disable button while dialog open or use route guard.
5. **Strengthen test E** — same `productId` on two purchase lines, return on one only.
6. **Add async race test** — select A, select B, assert B lines win.
7. **Add barrier-dismiss test** — assert clean state on reopen.

Optional: exclude `DRAFT` purchases from eligibility if product confirms CONFIRMED-only returns.

---

## Readiness Score

**89 / 100**

Deductions:
- -4 async stale-result race (R-04/R-05)
- -3 barrier dismiss / lifecycle (R-02/R-01)
- -2 test gaps for race and same-product (R-06/R-07)
- -2 minor hygiene / uncontrolled fields

Strengths: zero write path, SR.1 authority preserved, save disabled, 38/38 tests, clean SR.2 isolation.

---

## Final Decision

**GO TO HARDENING**

No architectural or financial-safety blockers. SR.3.1 is safe to proceed to a Hardening Pass. SR.3.2 posting integration must NOT begin until Hardening + Final Audit complete.