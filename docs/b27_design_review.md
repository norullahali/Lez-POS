# B27 Design Review — POS Checkout Operation-Intent Idempotency

**Date:** 2026-10-14  
**Mode:** DESIGN ONLY (no production/test/schema changes)  
**Baseline HEAD:** `6d3d1b78f8f598adbc82b4b7536500e369d7cf96`  
**Schema:** 51  
**Discovery:** `docs/b27_discovery_report.md` — verified independently against code  

---

## 1. Executive Summary

Discovery is **confirmed**. `PaymentDialog` assigns `_idempotencyKey ??= Uuid.v4()` inside widget state (`payment_dialog.dart`). Each `showDialog` creates a new state object, so reopening checkout after a committed sale (but before `clearCart()`) yields a **new key** while `PosSaleFingerprint` can be unchanged. B5 test 7 allows two sales.

**Approved design (Option C):** A **cart-slot-scoped checkout idempotency helper** owned by the checkout orchestration layer (`CartNotifier` + `_checkout()` in `pos_screen.dart`), binding **UUID v4 + B5 fingerprint hash**. `PaymentDialog` stops owning the key; the orchestrator calls `prepareKey()` immediately before `processSale`. **No B5 semantic changes. No schema change.**

---

## 2. Baseline

| Item | Value |
|------|-------|
| HEAD | `6d3d1b7` |
| B26 | CLOSED |
| B5 | `PosSaleService.processSale` + `pos_sale_idempotency` |
| B24 reference | `PosSettleDebtIdempotencyState` |

---

## 3. Current Checkout Architecture

```
_CartPanelState._checkout()                    [pos_screen.dart ~771]
  ├─ snapshot activeCart + session
  ├─ optional ManagerApprovalDialog → approvedByUserId
  ├─ showDialog(PaymentDialog) → PaymentInfo?
  │     └─ _confirm(): _idempotencyKey ??= v4()
  ├─ if payment == null → return
  ├─ CartNotifier.checkout → PosSaleService.processSale
  ├─ clearCart() on success
  └─ catch: clearLoyaltyPoints(); conflict snackbar
```

---

## 4. B5 Backend Contract (unchanged by B27)

| Condition | B5 behavior |
|-----------|-------------|
| Same key + same fingerprint | Replay |
| Same key + different fingerprint | PosSaleIdempotencyConflictException |
| Different key + same fingerprint | New sale (test 7) |

B27 must prevent the third row during normal UI retry/reopen. No B5 code changes.

---

## 5. Checkout Intent Definition

One checkout intent = one `PosSaleFingerprint.compute(...)` hash (`pos_sale_fingerprint.dart`):

| Input | Source at submit |
|-------|------------------|
| sessionId | Open session id |
| cartSlotId | CartSession.id (1–3) |
| items | Sorted: productId, effectiveQuantity, unitPrice, discount |
| invoiceDiscount | Cart |
| loyaltyPointsUsed / loyaltyDiscount | Payment if pointsUsed > 0, else cart (matches CartNotifier.checkout) |
| customerId | selectedCustomer?.id |
| payment | PaymentInfo method, cash, card, change, debt, points, loyaltyDiscount |
| approvedByUserId | Refund-limit approval when applicable |

Not in fingerprint: cart note, createdAt, dialog/widget identity.

**Rules:** Material change to any fingerprint input → new intent → new key. Reopen dialog / rebuild without fingerprint change → same intent. DB committed, cart not cleared → same intent → reuse key (B5 replay).

---

## 6. Multi-Cart Ownership

**Selected: Option C** — `Map<int, PosCheckoutIdempotencySlotState>` held by `CartNotifier` (helper: `PosCheckoutIdempotencyState`).

| Model | Verdict |
|-------|---------|
| A PaymentDialog instance | Reject — key lost on dispose |
| B Cart slot only, no fingerprint | Reject — stale after edits |
| C Slot + fingerprint (selected) | Accept |
| D B5 fingerprint dedup | Out of scope (B28) |

`switchCart` does not copy keys. `clearCart` clears checkout key; numeric slot id is reused but empty cart + cleared key starts fresh on next sale.

---

## 7. Payment / Cart Intent Changes

Invalidate checkout key when fingerprint would change:

- Hook `CartNotifier` mutators: add/remove/qty/return/discount/price, invoice discount, customer, loyalty, pricing/free-item sync.
- `prepareKey`: if `boundFingerprintHash != currentHash` → reset → new UUID.

Payment fields enter fingerprint only after PaymentDialog confirm. Session close/open changes sessionId in hash → new key automatically.

Do not invalidate: selectItem (UI index), switchCart, dialog rebuild.

---

## 8. Key Lifecycle

| Scenario | Behavior |
|----------|----------|
| A Fresh checkout (new fingerprint) | New UUID |
| B PaymentDialog opens | No key allocation in dialog |
| C Transient error before commit | Same key |
| D DB commit OK, UI fails before clearCart | Same key on retry |
| E Same key hits B5 again | Replay |
| F Success (including idempotentReplay) | clearCart + clear key |
| G Material intent change | New key |
| H Explicit cart reset / remove cart tab | Clear key |
| I PosSaleIdempotencyConflictException | Surface error; do not auto-rotate key |

`payment == null`: no processSale; retain bound key only for retry after failed submit with unchanged fingerprint.

---

## 9. UI State Ownership

Introduce **`PosCheckoutIdempotencyState`** (pure Dart, `@visibleForTesting`), analogous to B24 but:

- Bound to `(cartSlotId, fingerprintHash)`.
- `onIdempotencyConflict` **retains** key (B24 resets — opposite here).

**Owner:** `CartNotifier`. No SharedPreferences for keys.

**PaymentDialog:** remove `_idempotencyKey` / `_posCheckoutUuid`. Parent assigns key after confirm:

1. User confirms → `PaymentInfo` without key (or partial).
2. `_checkout()` computes fingerprint from snapshot + payment + session + approval.
3. `prepareCheckoutKey(cartSlotId, fingerprintHash)` → UUID.
4. `checkout(..., PaymentInfo(..., idempotencyKey: key))`.

---

## 10. Success / Failure Lifecycle

- `idempotentReplay: true` → same success path (clear cart, clear key, snackbar).
- Print failure remains non-fatal after commit.
- catch: retain checkout key except on success path clear.

---

## 11. clearCart / Reset Semantics

`clearCart()` keeps `CartSession.id` / `createdAt`, clears items. Must invoke `clearCheckoutKey(activeCartId)`.

Also clear on: `removeCart`, successful checkout (prefer `finally` after success so key clears even if `clearCart` throws).

Prevents binding a completed sale key to a new unrelated cart on the same slot.

---

## 12. Fingerprint Binding

Binding: `(cartSlotId, fingerprintHash) → idempotencyKey`. Use `PosSaleFingerprint.compute` only — no duplicate hash in UI.

---

## 13. Concurrency Model

- `_checkoutInFlight`: same-panel double submit (keep).
- Sticky key: retry/reopen same intent (B27).
- Both required. Parallel submits with same key defer to B5.

No Future.delayed in tests.

---

## 14. Conflict UX

On `PosSaleIdempotencyConflictException`:

1. Show clear Arabic message (parameters conflict with prior attempt).
2. Do **not** auto-generate a new key or silently retry.
3. User must change cart/payment (new fingerprint) or clear cart.

Replace current copy that suggests reopening payment alone resolves conflict.

---

## 15. Option Analysis

| Option | Retry-after-commit | Multi-cart | B5 change | Verdict |
|--------|-------------------|------------|-----------|---------|
| A Dialog-local | Poor | OK | No | Reject |
| B Slot-only | Medium | OK | No | Reject |
| C Orchestrator + fingerprint | Strong | Strong | No | **Select** |
| D B5 dedup | Strong | OK | Yes (test 7) | Defer B28 |

---

## 16. Selected Design

**Option C** — cart-slot map + fingerprint-bound sticky UUID on orchestrator; PaymentDialog is payment UI only.

---

## 17. Business Invariants

I1 One logical checkout intent → one stable key until success, reset, or material change.  
I2 Reopen PaymentDialog same intent → reuse key.  
I3 Post-commit UI failure → reuse key.  
I4 Material change → new key.  
I5 Slots do not share keys.  
I6 Same-key → B5 replay.  
I7 B5 semantics unchanged.  
I8 Success clears key.  
I9 Explicit cart reset clears key.  
I10 Conflict never auto-rotates key.  
I11 No schema change.  
I12 B5/B24/B25/B26 regressions green.

---

## 18. Test Matrix

1. Fresh key. 2. Dialog retry same key. 3. Reopen same intent. 4. Post-commit UI failure simulation. 5. Cart change new key. 6. Payment change new key. 7. Non-material rebuild same key. 8. Cart reset clears. 9. Success clears. 10. Replay = success. 11. Conflict no rotate. 12. Two slots independent. 13. Same-key concurrent UI guard. 14–17 B5/B24/B25/B26 regression.

File: `test/pos_checkout_idempotency_b27_test.dart`.

---

## 19. Expected Implementation Surface

| File | Change |
|------|--------|
| `lib/features/pos/pos_checkout_idempotency.dart` (new) | Helper |
| `lib/features/pos/providers/pos_provider.dart` | Map, prepareKey, invalidation, clearCart hook |
| `lib/features/pos/screens/pos_screen.dart` | _checkout wiring, replay, conflict copy |
| `lib/features/pos/screens/widgets/payment_dialog.dart` | Remove UUID ownership |
| `test/pos_checkout_idempotency_b27_test.dart` | New |

No schema, no `pos_sale_service.dart` semantic changes.

---

## 20. Schema Decision

**NO SCHEMA CHANGE.** `pos_sale_idempotency` remains the only persistence.

---

## 21. Risks / Limitations

- Multi-cart leakage → per-slot map.
- Stale key after clear → hook clearCart.
- Post-commit UI failure → primary B27 fix.
- **Process death** after commit before clear: in-memory key lost; cart may restore from SharedPreferences with items; **duplicate sale still possible** without durable pending-checkout store — **documented limitation**, not B27 scope.

---

## 22. Scope

**IN:** POS checkout operation-intent UI lifecycle.  
**OUT:** B5 dedup, schema, sessions, customer/supplier/inventory/print refactors.

---

## 23. Final Verdict

Checkout intent, multi-cart ownership, lifecycle, conflict handling, and test matrix are defined. No hidden B5 dependency.

**B27 DESIGN VERDICT:**  
**DESIGN APPROVED**