# Supplier Returns SR.3.3 - Pre-Phase Assessment

**Date:** 2026-08-10
**Mode:** READ-ONLY (no code, test, schema, or commit changes)

---

## 1. Baseline Verification

| Check | Result |
|-------|--------|
| Branch | main |
| Working tree | CLEAN |
| Local commits not pushed | 3 (SR.3.1, SR.3.2 Step 1, SR.3.2 Step 2) |
| Latest SR commit | 6666381 feat(supplier-returns): complete SR.3.2 history list UI |
| Schema version | 31 |
| Regression tests (verified) | 67/67 PASS |
| flutter analyze errors | 0 |
| Windows debug build | PASS |

---

## 2. Current Supplier Returns Map

### A. Database / schema (v31)

Tables: `supplier_returns`, `supplier_return_items`. Nullable `purchase_invoice_id`, `supplier_id`, `purchase_item_id` support legacy/manual rows. Index on `purchase_item_id` for returnable-qty sums.

### B-E. Header, lines, linkage

Header stores return number, date, total, reason, notes, optional supplier and purchase invoice. Lines store product, qty, unit cost, total, optional purchase item link.

### F. Returnable quantity contract (SR.1)

`getReturnableQuantityForPurchaseItem`: purchased_qty - SUM(linked return qty), clamped at 0; null purchaseItemId rows excluded.

### G-H. ReturnsDao APIs

**Read:** getReturnableQuantityForPurchaseItem, getSupplierReturnById, listSupplierReturnsHistory, getSupplierReturnItems.
**Write (low-level):** persistSupplierReturn (stock + RETURN_OUT), saveSupplierReturn (deprecated manual only, rejects purchase linkage).

### I. SupplierReturnService

Canonical purchase-linked posting: validates purchase/supplier/items/returnable qty inside one transaction, persists via persistSupplierReturn, records supplier RETURN transaction.

### J. Supplier accounting

`recordReturnInTransaction`: type RETURN, amount -returnValue, reduces payable; fully-paid case yields negative balance (supplier credit).

### K-L. Stock

persistSupplierReturn inserts RETURN_OUT stock ledger rows and StockGuard.deductStock once per line.

### M. Cash Ledger boundary

FinancialLedgerRepository includes supplier_transactions WHERE type = PAYMENT only. RETURN excluded. Goods returns create no Cash Ledger event (test J + hardening).

### N-P. Draft / read layer

Draft models + SupplierReturnDraftNotifier (ephemeral). SupplierReturnReadRepository: eligible purchases, draft lines, list, detail.

### Q-R. Posting providers

supplierReturnServiceProvider, buildPostingInputFromDraft(), Arabic failure mapping via supplierReturnPostingFailureMessage.

### S-U. History UI

SupplierReturnListItem/Detail models, supplierReturnsListProvider + search, supplierReturnDetailProvider + dialog.

### V. Refresh

supplierReturnsRefreshProvider tick incremented on successful post only; list watches tick; manual invalidate reloads.

### W. Screen

SupplierReturnsScreen: create dialog, history DataTable, search, refresh, detail dialog.

### X. Tests (67 total)

SR.1 11, SR.2 11, Hardening 4, SR.3.1 18, SR.3.2 Step 1 11, SR.3.2 Step 2 12.

### Y. Documentation

19 supplier_returns docs from SR.1 through SR.3.2 Step 2 final audit.

---

## 3. Current Functional Capability

| # | Capability | Classification |
|---|------------|----------------|
| 1 | Create purchase-linked supplier return | IMPLEMENTED AND CERTIFIED |
| 2 | Select original purchase | IMPLEMENTED AND CERTIFIED |
| 3 | Load purchase lines | IMPLEMENTED AND CERTIFIED |
| 4 | See returnable quantity | IMPLEMENTED AND CERTIFIED |
| 5 | Select quantities | IMPLEMENTED AND CERTIFIED |
| 6 | Enter reason | IMPLEMENTED AND CERTIFIED |
| 7 | Enter notes | IMPLEMENTED AND CERTIFIED |
| 8 | Save/post return | IMPLEMENTED AND CERTIFIED |
| 9 | Stock deduction | IMPLEMENTED AND CERTIFIED |
| 10 | Supplier payable adjustment | IMPLEMENTED AND CERTIFIED |
| 11 | Cash Ledger behavior (no event on goods return) | IMPLEMENTED AND CERTIFIED |
| 12 | Success feedback | IMPLEMENTED AND CERTIFIED |
| 13 | Failure feedback (Arabic) | IMPLEMENTED AND CERTIFIED |
| 14 | Retry after failure | IMPLEMENTED AND CERTIFIED |
| 15 | Return history | IMPLEMENTED AND CERTIFIED |
| 16 | Search/filter history (client-side, max 100) | IMPLEMENTED AND CERTIFIED |
| 17 | View return details | IMPLEMENTED AND CERTIFIED |
| 18 | Refresh after successful posting | IMPLEMENTED AND CERTIFIED |
| 19 | Manual/unlinked supplier returns (UI) | NOT IMPLEMENTED |
| 20 | Fully-paid purchase to supplier credit (ledger) | IMPLEMENTED AND CERTIFIED |
| 21 | Duplicate return-line protection | IMPLEMENTED AND CERTIFIED |
| 22 | Returnable quantity enforcement | IMPLEMENTED AND CERTIFIED |
| 23 | Legacy return compatibility (read path) | IMPLEMENTED AND CERTIFIED |
| 24 | Manual return creation (DAO only) | FOUNDATION ONLY |
| 25 | Cash refund from supplier | DEFERRED |
| 26 | Supplier credit settlement UX | DEFERRED |
| 27 | Reports/export | DEFERRED |
| 28 | Pagination / server search | DEFERRED |
| 29 | Idempotency keys | DEFERRED |

---

## 4. Architecture Boundaries (verified unchanged)

- UI does not perform financial writes directly.
- UI posts only via SupplierReturnService.postPurchaseLinkedReturn.
- Costs/products derived from purchase items in service layer.
- Returnable qty uses SR.1 contract.
- Stock posted once per line via persistSupplierReturn.
- Supplier accounting atomic inside service transaction.
- Goods returns do not create Cash Ledger events.
- Failure rolls back complete transaction.
- Legacy/manual rows readable in history with linkageLabel.
- Schema remains 31.

---

## 5. Deferred Work Inventory

| Item | Why deferred | Required now? | Phase fit |
|------|--------------|---------------|-----------|
| Cash refund settlement | SR.2 scope; goods-only posting | High for complete lifecycle | SR.3.3 candidate |
| Supplier credit UX | Accepted negative balance; no UI | Medium | SR.3.3 or SR.3.4 |
| Reports/export | Out of SR.3 UI scope | Optional | Later |
| Idempotency keys | No framework; double-submit guarded in UI | Medium reliability | SR.3.3+ |
| Pagination | History limited to 100 rows | Low until volume grows | SR.3.4+ |
| Server-side search | Client filter sufficient for 100 rows | Low | SR.3.4+ |
| Widget integration tests | Unit/provider tests sufficient for cert | Optional | Anytime |
| Manual return workflow redesign | Purchase-linked is canonical path | Low unless business requires | SR.3.4+ |
| Batch returnable-qty API | N+1 per line accepted | Low | When profiling shows pain |
| Arabic/domain error localization | Partially done in Step 1 | Low remaining | Hardening |
| Legacy history list test | Test gap only | No | Non-blocking |

---

## 6. Business Workflow Gap Analysis

**Complete today:** Purchase -> receive stock -> purchase-linked return -> stock decrease -> payable decrease -> history/audit of return header and lines.

**Gaps identified in code/docs:**

1. **Supplier credit after fully-paid return:** Ledger supports negative balance (hardening test). Supplier profile shows balance with green when negative, but no explicit credit-from-return explanation or link to return record.
2. **Cash refund from supplier:** Not implemented. No Cash Ledger SUPPLIER_REFUND or equivalent. Payment screen only records PAYMENT to supplier, not receiving cash when supplier owes store.
3. **Using credit against future payment:** Mathematically balance net applies, but no guided UX to settle credit or record supplier cash refund.
4. **Manual returns:** DAO path exists (stock only, no accounting) but no UI; not part of certified user workflow.
5. **Reporting:** No supplier-returns-specific export or financial report integration.

Reason/notes are persisted and visible in detail dialog. Traceability to original purchase and lines is strong for purchase-linked returns.

---

## 7. Data / Accounting Integrity

Current model is sufficient for purchase-linked returns and read-only history. Structural observations (recommendations only, no schema change now):

- Supplier credit is implicit via negative currentBalance; no separate credit entity or settlement link table.
- Cash refund would need new transaction type and Cash Ledger integration (documented gap since SR.2).
- Idempotency would benefit from client token or unique constraint on return_number if enforced.
- Manual returns lack supplier accounting by design; expanding manual workflow may need service boundary decision.

---

## 8. UX Gap Review

**Strong:** Arabic RTL create flow, purchase search, returnable qty visibility, draft total, posting overlay, failure retry, history list, linkage badges, detail dialog.

**Meaningful gaps:**
- No visibility of resulting supplier balance/credit after post.
- No cash refund or credit settlement action from return context.
- No manual return UI.
- History search limited to 100 rows (accepted).
- Supplier profile transaction history may not highlight RETURN rows with return reference (not verified in depth; general supplier txn list exists).

---

## 9. Performance Review

| Concern | Classification |
|---------|----------------|
| Draft line load (N returnable queries) | ACCEPTED for typical invoice sizes |
| History list single query | SAFE NOW |
| Client search on 100 rows | ACCEPTED |
| Detail bounded enrichment (2 lookups) | ACCEPTED |
| Large return history without pagination | SHOULD BE ADDRESSED SOON (when volume grows) |
| Multi-branch scale | FUTURE SCALE WORK |

---

## 10. Test Coverage Review

**Verified: 67/67 PASS** (re-run 2026-08-10).

**Well covered:** returnable qty, posting service atomicity, bypass guard, fully-paid credit, draft race, posting integration, refresh contract, history list/detail side effects.

**Meaningful gaps (non-blocking):** legacy manual return in history list, search filter unit test, widget tests, multi-line detail test, explicit cash refund settlement (not implemented), idempotency under rapid network retry.

---

## 11. Security / Safety Findings

| ID | Finding | Class |
|----|---------|-------|
| S-01 | UI does not send unit cost to service | ACCEPTED |
| S-02 | F-01 bypass guard on saveSupplierReturn | ACCEPTED |
| S-03 | Double-submit guarded (canSave + isPosting + tests) | ACCEPTED |
| S-04 | No idempotency key on post | DEFERRED |
| S-05 | persistSupplierReturn public on DAO | NON-BLOCKING (documented) |
| S-06 | Legacy manual path skips supplier accounting | ACCEPTED (by design) |

BLOCKERS: 0 | REQUIRES ACTION: 0

---

## 12. Next-Phase Options

### Option A - Cash Refund / Supplier Credit Settlement
Goal: Complete financial lifecycle when return creates supplier credit or cash is received from supplier.
Value: High. Dependencies: SR.2 credit semantics, Cash Ledger patterns. Schema: likely new txn type / ledger event. Risk: Medium. Complexity: Medium-High.

### Option B - Reporting / Export
Goal: Supplier returns in financial reports and export.
Value: Medium. Dependencies: history read APIs exist. Schema: none. Risk: Low. Complexity: Medium.

### Option C - Manual Supplier Return Workflow
Goal: UI for unlinked returns via controlled service path.
Value: Low-Medium. Dependencies: saveSupplierReturn or new service. Schema: none. Risk: Medium (accounting ambiguity). Complexity: Medium.

### Option D - UX / Accounting Visibility
Goal: Post-return balance preview, credit messaging, link to supplier profile.
Value: Medium. Dependencies: existing balance APIs. Schema: none. Risk: Low. Complexity: Low-Medium.

### Option E - Reliability / Idempotency
Goal: Prevent duplicate returns on retry/double-submit at service layer.
Value: Medium. Dependencies: none. Schema: optional unique keys. Risk: Low. Complexity: Medium.

---

## 13. Recommended Roadmap

### RECOMMENDED NEXT PHASE

**Name:** SR.3.3 - Supplier Credit & Cash Refund Settlement

**Objective:** Close the business loop after goods return when supplier owes the store money: represent credit clearly, support recording cash received from supplier, integrate with Cash Ledger where appropriate, without altering SR.2 goods-return posting.

**Why now:** Purchase-linked return + history is complete. Hardening already certifies negative-balance credit semantics but provides no settlement path. Financial docs flag supplier cash refunds as a known Cash Ledger gap.

**Dependencies:** Certified SR.2 posting, supplier_accounts RETURN transactions, FinancialLedgerRepository patterns, supplier profile balance display.

**Should include:** Settlement UX (from supplier profile and/or return context), cash-in ledger event for supplier refund, explicit credit visibility, tests for ledger + balance, documentation.

**Must NOT include:** Rewriting SR.2 posting, pagination overhaul, manual return redesign, broad reports module.

**Schema impact:** Possible new supplier transaction subtype or Cash Ledger source; assess during planning only.

**Risk:** Medium - touches financial boundaries.

**Expected tests:** Credit-after-return baseline + cash refund posting + no duplicate ledger + SR.2 regression 67/67 unchanged.

**Expected outcome:** Store can return goods, see supplier credit, and record cash received from supplier with audit trail.

### SECOND PRIORITY
SR.3.4 - Supplier Returns Reporting & Export (list/export, supplier txn drill-down).

### THIRD PRIORITY
SR.3.5 - History scale (pagination + server-side search) when return volume warrants.

---

## 14. Final Decision

**GO TO NEXT PHASE PLANNING**

No blockers prevent planning SR.3.3. Working tree clean, 67/67 regression pass, architecture boundaries intact.