# Customer Returns Phase C Step 2.2 — Cash Ledger Integration

**Date:** 2026-08-18  
**Schema:** 31 (unchanged)  
**Baseline:** Step 2.1 commit `a01993d`

---

## 1. Objective

Derive `CUSTOMER_REFUND` Cash Ledger **outflow** events from committed `customer_transactions` rows where `type = 'REFUND'` and `amount > 0`.

No settlement service changes. No ledger persistence table.

---

## 2. Architecture

```
CustomerRefundSettlementService.settleCredit()   [UNCHANGED Step 2.1]
        ↓
customer_transactions REFUND (+amount)
        ↓
FinancialLedgerRepository UNION (read-only)
        ↓
CashLedgerEvent CUSTOMER_REFUND (outflow)
```

Hybrid derived ledger — identical pattern to Supplier SR.3.3 Step 2 (`SUPPLIER_REFUND` inflow).

---

## 3. CUSTOMER_REFUND semantics

| Property | Value |
|----------|-------|
| Business meaning | Cash paid from business to customer against accumulated credit |
| Source | `customer_transactions WHERE type='REFUND' AND amount>0` |
| Direction | **outflow** |
| Amount | Positive magnitude (`ct.amount`) |
| Distinct from | `RETURN` (goods reversal), `RETURN_REFUND` (immediate POS cash return via audit log) |

**RETURN != REFUND**

---

## 4. Event contract

| Field | Value |
|-------|-------|
| `ledger_id` | `CUSTOMER_REFUND:` \|\| `ct.id` |
| `event_type` | `CUSTOMER_REFUND` |
| `direction` | `outflow` |
| `reference_type` | `customer_transaction` |
| `reference_id` | `ct.id` |
| `customer_id` | `ct.customer_id` |
| `invoice_id` | `customer_returns.original_invoice_id` when `ct.reference_id` links a return |

---

## 5. UNION branch

Added to `FinancialLedgerRepository._unionSql` after `CUSTOMER_PAYMENT`:

- Filters `type = 'REFUND' AND amount > 0`
- `LEFT JOIN customer_returns` for invoice traceability
- Default Arabic description: `استرداد نقدي للعميل`

---

## 6. Direction convention

Accounting stores positive REFUND amounts. Cash Ledger uses positive magnitude + `direction = outflow` (mirror of `SUPPLIER_REFUND` inflow).

---

## 7. Exact-once derivation

One committed REFUND row → one derived event via primary-key-based `ledger_id`. No second persistence layer.

---

## 8. Traceability

Cash Ledger → customer transaction → optional customer return → original sales invoice.

---

## 9. Return isolation

- `customer_transactions RETURN` does **not** produce `CUSTOMER_REFUND`
- `RETURN_REFUND` branch unchanged
- Step 2.1 settlement service/DAO/tests unchanged

---

## 10. Files changed

| Action | File |
|--------|------|
| MODIFIED | `lib/features/financial/models/cash_ledger_event_type.dart` |
| MODIFIED | `lib/features/financial/repositories/financial_ledger_repository.dart` |
| MODIFIED | `lib/features/financial/widgets/cash_ledger_event_drill_down.dart` |
| MODIFIED | `lib/features/financial/screens/widgets/dashboard_recent_activity_row.dart` |
| NEW | `test/customer_refund_cash_ledger_phase_c_step_2_2_test.dart` |

Auto-propagating (no change required): Cash Ledger screen dropdown, dashboard analytics breakdown, export helper.

---

## 11. Tests

`test/customer_refund_cash_ledger_phase_c_step_2_2_test.dart` — matrix A–P (16 tests).

**Focused: 16/16 PASS**

---

## 12. Regression

| Suite | Result |
|-------|--------|
| Step 2.2 focused | 16/16 PASS |
| Step 2.1 | 17/17 PASS |
| Phase C Step 1 | 20/20 PASS |
| Supplier refund + cash ledger | 27/27 PASS |
| Supplier UI/profile | 27/27 PASS |
| **Full combined** | **107/108 PASS** |

Sole failure: `test/cash_ledger_forensic_runtime_test.dart` (pre-existing debugPrint harness).

---

## 13. Analyzer (Step 2.2 scope)

**0 errors / 0 warnings / 0 infos**

---

## 14. Windows build

**PASS**

---

## 15. Schema

**31 → 31** — no migration.

---

## 16. Known limitations

- No Customer Profile refund UI
- Forensic harness failure pre-existing
- Partial return may still produce separate `RETURN_REFUND` audit events; `CUSTOMER_REFUND` remains isolated

---

## 17. Deferred work

- Customer refund UI (profile/dialog)
- Arabic failure mapper
- Idempotency framework
- Per-return settled_amount tracking

---

## 18. Final status

**IMPLEMENTATION COMPLETE — READY FOR REVIEW PASS**

Direct Cash Ledger writes: **0**  
Step 2.1 service: **UNCHANGED**