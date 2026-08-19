# Customer Returns Phase C Step 2.2 — Pre-Phase Assessment

**Date:** 2026-08-18  
**Mode:** READ-ONLY / ARCHITECTURE ASSESSMENT  
**Schema:** 31 (unchanged)  
**Protected baseline:** `a01993d` (Step 2.1 committed)

---

## 1. Executive Summary

Customer Returns Phase C Step 2.2 can integrate **derived Cash Ledger visibility** for customer cash-refund settlement **without schema changes, without new ledger persistence, and without modifying the certified Step 2.1 settlement service**.

The implementation adds one new UNION branch to `FinancialLedgerRepository`, one new `CashLedgerEventType`, minimal UI wiring (drill-down + dashboard icon), and a focused test file mirroring the certified Supplier SR.3.3 Step 2 pattern.

**Correct cash movement:** business pays cash **to** the customer → **`CUSTOMER_REFUND` = OUTFLOW** (positive magnitude + `direction = outflow`).

> Note: Section 1 of the task brief mentions “inflow” in the target flow diagram; business semantics and Section 7 are authoritative. Supplier `SUPPLIER_REFUND` is **inflow** (cash received); customer `CUSTOMER_REFUND` is the **mirror outflow** (cash paid out).

**FINAL RECOMMENDATION: READY FOR IMPLEMENTATION**

---

## 2. Protected Step 2.1 Baseline

Commit `a01993d` — **must not change** in Step 2.2:

| Component | Protected behavior |
|-----------|-------------------|
| `CustomerRefundSettlementService.settleCredit()` | Single txn; validation; credit calc; optional return linkage |
| `CustomerAccountsDao.recordRefundInTransaction()` | Low-level REFUND persist (+amount) |
| `customer_transactions` REFUND contract | `type='REFUND'`, positive amount, optional `referenceId`, optional note |
| Credit semantics | `availableCredit = balance < 0 ? -balance : 0` |
| Activity log | `CUSTOMER_REFUND` inside same Drift transaction |
| Failure contract | 7 typed failures + rollback |
| Tests | `test/customer_refund_settlement_phase_c_step_2_test.dart` (17/17) |

Step 2.2 is **read-model only** — settlement path stays frozen.

---

## 3. Existing Customer Refund Architecture (Actual Code)

### Service (`customer_refund_settlement_service.dart`)

```
settleCredit()
  db.transaction {
    validate customer / amount / optional returnId
    balance = calculateBalanceFromTransactions(customerId)
    availableCredit = balance < 0 ? -balance : 0
    reject if no credit or over-credit
    recordRefundInTransaction(type REFUND, +amount)
    [test hooks]
    logsDao.insertLog(actionType: CUSTOMER_REFUND)
  }
```

- No Cash Ledger call today (comment: deferred to separate step).
- Return linkage: `customer_returns.id → originalInvoiceId → sales_invoices.customerId`.

### DAO (`recordRefundInTransaction`)

```dart
applyTransaction(type: 'REFUND', amount: amount, referenceId: returnId, note: note)
```

- Persists **positive** amount.
- Updates `customer_accounts.currentBalance` via transaction sum.

### Persisted REFUND row contract (authoritative)

| Field | Value |
|-------|-------|
| `type` | `'REFUND'` |
| `amount` | Positive settlement amount |
| `referenceId` | Optional `customer_returns.id` |
| `note` | Optional string |
| `customerId` | Required owner |

**Not in Cash Ledger today** — Step 2.2 adds derived visibility only.

---

## 4. Existing Cash Ledger Architecture

### Hybrid derived ledger

- **No ledger table.** No INSERT API.
- `FinancialLedgerRepository._unionSql` UNIONs operational sources.
- Each row: `ledger_id`, `event_ts`, `event_type`, `amount`, `direction`, `reference_type`, `reference_id`, `user_id`, `customer_id`, `supplier_id`, `invoice_id`, `description`.
- `CashLedgerEvent` is read-only mapped from query results.
- Summary, pagination, export, dashboard cash-flow/breakdown all wrap `_unionSql`.

### Current customer-related branches

| Branch | Source | Direction |
|--------|--------|-----------|
| `SALE_CASH` | `sales_invoices.cash_paid > 0` | inflow |
| `CUSTOMER_PAYMENT` | `customer_transactions WHERE type='PAYMENT'` | inflow |
| `RETURN_REFUND` | `return_audit_logs.returned_amount > 0` | outflow |

**Not in UNION today:**

- `customer_transactions WHERE type='RETURN'` (correct — credit reversal, not cash)
- `customer_transactions WHERE type='REFUND'` (**Step 2.2 target**)

### Double-count guard (RETURN_REFUND)

`RETURN_REFUND` excludes rows when a matching `customer_transactions RETURN` exists for the same invoice via `customer_returns.original_invoice_id`. This protects Phase C credit-return paths from duplicating cash events.

**Integration boundary confirmed:** `FinancialLedgerRepository` is the correct and only integration point.

---

## 5. Supplier Refund Reference Architecture

Certified pattern (SR.3.3 Step 2, commit `c4ff8e7`, doc `supplier_returns_sr_3_3_step_2_cash_ledger_integration.md`):

```
supplier_transactions REFUND (+amount)
    ↓ UNION (read)
SUPPLIER_REFUND
    direction = inflow
    amount = st.amount (positive)
```

- Settlement service **unchanged** after Step 1.
- Exactly one ledger event per committed REFUND row (`ledger_id = 'SUPPLIER_REFUND:' || st.id`).
- Optional return trace: `LEFT JOIN supplier_returns ON sr.id = st.reference_id` → `invoice_id = purchase_invoice_id`.
- Tests: `test/supplier_refund_cash_ledger_sr_3_3_step_2_test.dart` (14/14).

---

## 6. Customer vs Supplier Semantic Comparison

| Aspect | SUPPLIER_REFUND | CUSTOMER_REFUND (proposed) |
|--------|-----------------|---------------------------|
| **Business meaning** | Cash received from supplier against supplier credit | Cash paid to customer against customer credit |
| **Source table** | `supplier_transactions` | `customer_transactions` |
| **Transaction type** | `REFUND` | `REFUND` |
| **Stored amount sign** | Positive | Positive |
| **Balance effect** | Credit consumed (balance → 0) | Credit consumed (balance → 0) |
| **Cash direction** | **inflow** | **outflow** |
| **Enum `isInflow`** | `true` | `false` |
| **Running balance** | Increases | Decreases |
| **Goods return txn** | `RETURN` (negative) — no ledger event | `RETURN` (negative) — no ledger event |
| **reference_type** | `supplier_transaction` | `customer_transaction` |
| **reference_id** | supplier txn id | customer txn id |
| **Party id column** | `supplier_id` | `customer_id` |
| **Invoice trace** | `supplier_returns.purchase_invoice_id` | `customer_returns.original_invoice_id` |
| **Label (AR)** | استرداد من مورد | استرداد نقدي للعميل (proposed) |
| **Drill-down** | Supplier profile | Customer profile (mirror `CUSTOMER_PAYMENT`) |
| **Dashboard icon** | `Icons.call_received_rounded` | `Icons.call_made_rounded` or `payments_outlined` (proposed) |

**RETURN != REFUND** on both sides. Step 2.2 must not conflate customer goods RETURN with customer cash REFUND.

---

## 7. Proposed CUSTOMER_REFUND Event Contract

| Property | Value |
|----------|-------|
| **Code** | `CUSTOMER_REFUND` |
| **Enum** | `CashLedgerEventType.customerRefund` |
| **Label (AR)** | استرداد نقدي للعميل |
| **Source** | `customer_transactions WHERE type = 'REFUND' AND amount > 0` |
| **ledger_id** | `'CUSTOMER_REFUND:' \|\| ct.id` |
| **event_ts** | `ct.created_at` |
| **amount** | `ct.amount` (positive magnitude) |
| **direction** | `'outflow'` |
| **reference_type** | `'customer_transaction'` |
| **reference_id** | `ct.id` |
| **customer_id** | `ct.customer_id` |
| **supplier_id** | `NULL` |
| **invoice_id** | `cr.original_invoice_id` when `ct.reference_id` links `customer_returns` |
| **description** | `COALESCE(NULLIF(ct.note,''), 'استرداد نقدي للعميل')` |

---

## 8. Amount / Direction Convention

Follow existing repository convention (same as SUPPLIER_REFUND, inverted direction):

- **Accounting source of truth:** positive `REFUND` amount in `customer_transactions`.
- **Cash Ledger:** always store **positive magnitude** in `amount`; encode flow via **`direction`** (`outflow`), not negative amounts.
- **`CashLedgerEventType.isInflow`** must be `false` for filter/breakdown fallbacks.

This matches `RETURN_REFUND`, `SUPPLIER_PAYMENT`, `EXPENSE` outflow branches.

---

## 9. Exact-Once Derivation

**Mechanism:**

1. Primary key `customer_transactions.id` is unique.
2. UNION filter `type = 'REFUND' AND amount > 0` selects only settlement rows.
3. `ledger_id = 'CUSTOMER_REFUND:' || ct.id` is deterministic and unique per txn.
4. No second persistence layer — committed REFUND row is the sole source.

**Guarantees:**

- 1 committed REFUND → exactly 1 CUSTOMER_REFUND event visible in `getEntries()` / `getSummary()`.
- 0 REFUND (validation failure / rollback) → 0 events (derived read sees nothing).
- No duplicate from RETURN branch (`type='RETURN'` excluded).
- No duplicate from RETURN_REFUND branch (different source table; credit-return guard already excludes overlapping audit rows).

---

## 10. Atomicity Model

```
CustomerRefundSettlementService.settleCredit()
  db.transaction {
    REFUND write
    CUSTOMER_REFUND activity log
  }
  COMMIT
      ↓
FinancialLedgerRepository (derived SELECT / UNION)
      ↓
CUSTOMER_REFUND visible on next read
```

**Why correct:**

- Cash Ledger is derived — no second write, no second transaction.
- If settlement rolls back, REFUND row never commits → UNION cannot surface an event.
- Activity log inside same txn — rollback removes both (Step 2.1 test M proven).
- Read-after-commit is the established Hybrid Model (identical to SUPPLIER_REFUND, EXPENSE, OTHER_INCOME).

**Do NOT:** add ledger INSERT, ledger table, or post-commit Cash Ledger hook in service.

---

## 11. Traceability Model

**Proposed chain:**

```
Cash Ledger CUSTOMER_REFUND
  → customer_transactions (reference_type customer_transaction, reference_id = ct.id)
  → optional customer_returns (ct.reference_id)
  → sales_invoices (cr.original_invoice_id)
  → customer (ct.customer_id)
```

**Fields use existing schema only** — no new columns.

**Drill-down recommendation:** open customer profile (same guard as `CUSTOMER_PAYMENT`: `customerId > 1`).

Optional future enhancement (deferred): invoice drill-down when `invoice_id` populated — not required for Step 2.2 parity with supplier pattern.

---

## 12. Goods Return Isolation

**Hard boundary — no Step 2.2 changes to:**

- `customer_transactions RETURN` posting
- `CustomerReturnCredit` / `PartialReturnService` / `ReturnsDao` return accounting
- `sale_item_returns` semantics
- Existing `RETURN_REFUND` UNION branch or its credit-return guard

**Expected test N:** customer goods RETURN (credit invoice partial return) produces **zero** `CUSTOMER_REFUND` events.

**Distinction from RETURN_REFUND:**

| Event | When | Source |
|-------|------|--------|
| `RETURN_REFUND` | Immediate POS cash refund at return time | `return_audit_logs` |
| `CUSTOMER_REFUND` | Later settlement of accumulated customer credit | `customer_transactions REFUND` |

These are complementary, not overlapping, for normal Phase C flows.

---

## 13. UI Boundary

Step 2.2 scope: **Cash Ledger integration only.**

**Out of scope (deferred):**

- Customer Profile refund button / dialog
- Arabic failure mapper
- Double-submit UI guard
- Any change to `CustomerRefundSettlementService` API

Existing Step 2.1 service remains the **only** financial settlement entry point.

**Minimal UI touch (presentation only):**

- `CashLedgerEventType` filter dropdown (auto via enum values)
- `CashLedgerEventDrillDown` — add `customerRefund` case
- `dashboard_recent_activity_row.dart` — icon/accent mapping

---

## 14. Schema Assessment

**Schema migration required: NO**

- `customer_transactions.type` is free-text; `REFUND` already persisted by Step 2.1.
- `customer_returns`, `sales_invoices`, `customer_accounts` unchanged.
- `_readSet()` already includes `customerTransactions` and `customerReturns`.

**31 → 31** — no table, column, index, or migration.

**Design blocker if schema change needed:** None identified.

---

## 15. Exact Files Proposed for Step 2.2

| File | Change | Why | Must remain untouched |
|------|--------|-----|----------------------|
| `lib/features/financial/models/cash_ledger_event_type.dart` | Add `customerRefund` enum value | New event type for filter/UI/breakdown | Existing enum values |
| `lib/features/financial/repositories/financial_ledger_repository.dart` | Add UNION branch + comment | Core derived integration | All other UNION branches |
| `lib/features/financial/widgets/cash_ledger_event_drill_down.dart` | Add `customerRefund` case → customer profile | UX parity with `CUSTOMER_PAYMENT` | Other drill-down routes |
| `lib/features/financial/screens/widgets/dashboard_recent_activity_row.dart` | Icon for `customerRefund` | Dashboard recent activity display | Other icons |
| `test/customer_refund_cash_ledger_phase_c_step_2_2_test.dart` | **NEW** focused tests | Certification matrix A-O+ | — |
| `docs/customer_returns_phase_c_step_2_2_cash_ledger_integration.md` | **NEW** implementation doc | Certification artifact | — |

**Explicitly NOT modified:**

- `customer_refund_settlement_service.dart`
- `customer_accounts_dao.dart`
- `partial_return_service.dart`, `customer_return_credit.dart`, `returns_dao.dart`
- Supplier Returns files
- Schema / migrations
- Customer Profile / refund UI

**Auto-propagating (likely no code change):**

- `cash_ledger_screen.dart` dropdown (uses `CashLedgerEventType.values`)
- `financial_dashboard_cash_analytics.dart` (uses `fromCode` on UNION output)
- `cash_ledger_export_helper.dart` (generic fields)

---

## 16. Focused Test Matrix (Step 2.2)

Proposed file: `test/customer_refund_cash_ledger_phase_c_step_2_2_test.dart`

| ID | Scenario |
|----|----------|
| A | Customer REFUND produces one `CUSTOMER_REFUND` event |
| B | Event amount is positive magnitude |
| C | Direction is outflow; `isInflow == false`; summary `totalOutflow` increases |
| D | `customer_transactions RETURN` alone → zero `CUSTOMER_REFUND` |
| E | `PAYMENT` → zero `CUSTOMER_REFUND` |
| F | `SALE` → zero `CUSTOMER_REFUND` |
| G | Exactly one event per committed REFUND |
| H | Multiple REFUND rows → corresponding multiple events |
| I | `reference_type == customer_transaction`, `reference_id == ct.id` |
| J | `customer_id` correct on event |
| K | Return-linked REFUND → `invoice_id == original_invoice_id` |
| L | Rollback (post-refund hook) → 0 REFUND, 0 visible CUSTOMER_REFUND |
| M | Accounting failure override → 0 REFUND, 0 events |
| N | Supplier `SUPPLIER_REFUND` unchanged (regression spot-check) |
| O | Customer credit RETURN (partial) → no CUSTOMER_REFUND; RETURN_REFUND guard unchanged |
| P | Existing UNION branches spot-check (SALE_CASH, CUSTOMER_PAYMENT counts stable) |

Use real `AppDatabase.test()`, `CustomerRefundSettlementService`, `FinancialLedgerRepository` — mirror supplier Step 2 test structure.

---

## 17. Regression Plan

Must remain green after Step 2.2:

| Suite | Expected |
|-------|----------|
| Step 2.1 focused | 17/17 PASS |
| Phase C Step 1 | 20/20 PASS |
| Supplier refund settlement | 13/13 PASS |
| Supplier cash ledger | 14/14 PASS |
| Supplier UI/profile (optional full suite) | unchanged |
| Full combined regression | 91/92 PASS |

**Accepted baseline failure (do not reclassify):**

- `test/cash_ledger_forensic_runtime_test.dart` — global `debugPrint` foundation invariant (pre-existing, proven on HEAD before Step 2.1).

If forensic harness changes during Step 2.2 implementation, treat separately — do not modify production code merely to satisfy it.

---

## 18. Risks / Edge Cases

| Risk | Severity | Mitigation |
|------|----------|------------|
| Confusing CUSTOMER_REFUND with RETURN_REFUND | Medium | Clear labels; tests D, O; documentation |
| Accidental service modification | High | Step 2.2 scope lock; code review gate |
| Double-count if REFUND rows duplicated | Low | PK-based ledger_id; service enforces one txn per call |
| Aggregate refund without returnId (invoice_id NULL) | Low | Accept NULL; drill-down to customer |
| `customer_transactions` table comment omits REFUND | Low | Optional doc comment only — not required for Step 2.2 |
| Brief task doc says “inflow” | Low | Implement **outflow** per business semantics |

**No financial architecture conflict identified.**

---

## 19. Deferred Work

- Customer Profile refund UI / dialog (Step 3+)
- Arabic UI failure mapper
- UI double-submit protection
- Generic idempotency framework
- Per-return settled_amount tracking
- `CustomerReturnService` refactor
- Invoice drill-down from CUSTOMER_REFUND (optional enhancement)
- Forensic harness fix (separate maintenance)

---

## 20. Implementation Sequence

1. **Add enum** `CashLedgerEventType.customerRefund` (`isInflow: false`, AR label).
2. **Add UNION branch** in `FinancialLedgerRepository._unionSql` (after `CUSTOMER_PAYMENT` or before `RETURN_REFUND` — group customer events together).
3. **Verify `_readSet()`** already includes required tables (no change expected).
4. **Wire drill-down** — `customerRefund` → customer profile.
5. **Wire dashboard icon** in `dashboard_recent_activity_row.dart`.
6. **Create focused tests** (matrix A-P).
7. **Run regression suite** (91/92 + new focused tests).
8. **Run analyzer, format (Step 2.2 files only), Windows build**.
9. **Write implementation + review + audit docs** (follow Step 2.1 discipline).

**Estimated production touch:** 3–4 files + 1 test file + docs.

---

## 21. Certification Gates (for Step 2.2 implementation)

- [ ] Step 2.1 service/DAO/tests unchanged
- [ ] One REFUND → one CUSTOMER_REFUND outflow
- [ ] RETURN / PAYMENT / SALE do not emit CUSTOMER_REFUND
- [ ] Rollback → zero visible events
- [ ] Supplier SUPPLIER_REFUND regression green
- [ ] Phase C.1 + Step 2.1 regression green
- [ ] Schema 31 unchanged
- [ ] 0 analyzer errors on Step 2.2 scope
- [ ] Windows build PASS

---

## 22. Final Recommendation

**READY FOR IMPLEMENTATION**

All prerequisites satisfied:

- Step 2.1 fully protected at `a01993d`
- Hybrid Cash Ledger supports derived CUSTOMER_REFUND without schema change
- No ledger persistence required
- Event contract unambiguous (outflow, positive magnitude, REFUND source)
- Atomicity model clear (settlement txn only; derived read after commit)
- Traceability supported via existing columns + `customer_returns` join
- Test matrix defined
- No financial architecture conflict

---

**Assessment complete — no implementation performed.**