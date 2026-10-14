# B27 Review Pass — POS Checkout Operation-Intent Idempotency

**Date:** 2026-10-14  
**Mode:** READ-ONLY review (no production code changes)  
**Baseline HEAD:** `6d3d1b78f8f598adbc82b4b7536500e369d7cf96`  
**Schema:** 51  

## 1. Executive verdict

Implementation matches approved **Option C** and closes the primary duplicate-checkout gap (new PaymentDialog UUID per instance). The post-commit retry path reuses the sticky key stored on `CartNotifier` and reaches B5 replay when the cart/payment fingerprint is unchanged.

**REVIEW PASS**

Ready for Final Audit.

---

## 2. Baseline

| Item | Value |
|------|-------|
| HEAD | `6d3d1b7` |
| B27 design | APPROVED (Option C) |
| Commit/push | Not performed in this review |

---

## 3. Files reviewed

**Production**
- `lib/features/pos/pos_checkout_idempotency.dart`
- `lib/features/pos/providers/pos_provider.dart`
- `lib/features/pos/screens/pos_screen.dart`
- `lib/features/pos/screens/widgets/payment_dialog.dart`

**Tests**
- `test/pos_checkout_idempotency_b27_test.dart`

**Reference (unchanged)**
- B5: `pos_sale_service.dart`, `pos_sale_fingerprint.dart`, `test/pos_sale_idempotency_b5_test.dart`
- B24/B25/B26 regression suites

**Docs**
- `docs/b27_discovery_report.md`, `docs/b27_design_review.md`, `docs/b27_implementation_report.md`

---

## 4. Critical post-commit retry analysis

**Scenario steps 1–11 — PASS (code proof)**

| Step | Evidence |
|------|----------|
| Payment confirm | `PaymentDialog` pops `PaymentInfo` without UUID (`idempotencyKey: ''`) |
| Fingerprint | `cartNotifier.computeCheckoutFingerprint(...)` → `PosSaleFingerprint.compute` only |
| Sticky UUID | `prepareCheckoutKey(cartSlotId, fingerprintHash)` before `processSale` |
| Commit + UI fail | `catch` does **not** call `clearCheckoutKey`; cart not cleared |
| Reopen checkout | New dialog; orchestrator runs `prepareCheckoutKey` again |
| Same fingerprint | `idempotencyKey ??= generateUuid()` reuses bound key |
| B5 replay | Same key + same hash → `ProcessSaleResult.idempotentReplay` (test 5) |

**Not guaranteed (approved out of scope):** process death after commit loses in-memory key (Section 12).

**No correctness blocker** for the discovered vulnerability under normal in-process retry.

---

## 5. Key ownership review — PASS

| Check | Result |
|-------|--------|
| PaymentDialog UUID ownership | **Removed** (no `Uuid` / `v4` in file) |
| Authoritative owner | `CartNotifier.checkoutIdempotency` |
| Per-slot map | `PosCheckoutIdempotencyState._slots` keyed by `cartSlotId` |
| `switchCart` | Does not copy or move keys |
| `clearCart` | Clears key for active slot id |
| `removeCart` | `removeSlot(cartId)` |
| Slot reuse | `clearCart` clears key before empty slot reused |

---

## 6. Fingerprint binding review — PASS

- Single authority: `PosSaleFingerprint.compute` via `computeCheckoutFingerprint` and `checkout()`.
- No duplicate hash algorithm in UI.
- Loyalty fields follow B5 checkout rules (payment overrides cart when `pointsUsed > 0`).
- `idempotencyKey` is **not** part of fingerprint payload (B5-F1).

**Mutation vs fingerprint:** Material cart/payment changes either (a) call `_invalidateCheckoutKeyForActiveSlot()` or (b) change hash so `prepareCheckoutKey` resets slot state. `selectItem` does not invalidate (non-fingerprint) — PASS.

---

## 7. Material / non-material mutation review — PASS

| Case | Behavior |
|------|----------|
| A Material cart change | Invalidation hook and/or new fingerprint → new UUID |
| B Non-material rebuild | Same fingerprint → same key (tests 2, 3, 8) |
| C Payment change | New fingerprint → new key (test 7) |
| D Session change | `sessionId` in fingerprint → new key |
| E Reopen dialog | Orchestrator `prepareCheckoutKey` — same key if intent unchanged |

**Note (OPTIONAL):** Eager invalidation on any cart mutator clears the key even if the user later restores an identical fingerprint; could mint a new UUID in a rare revert scenario. Primary post-commit retry without cart edits remains safe.

---

## 8. Failure lifecycle review — PASS

| Path | Key behavior |
|------|----------------|
| Dialog cancelled (`payment == null`) | No `prepareCheckoutKey`; prior bound key retained if any |
| Pre-commit failure | `catch`: retains key; `clearLoyaltyPoints` only |
| Success / replay | Success path: `clearCheckoutKey` + `clearCart` |
| Print failure | Swallowed; sale still success path → key cleared |
| Conflict | `catch`: retains key; updated Arabic message |

No `finally` block clears the checkout key early.

---

## 9. Concurrency review — PASS

- `_checkoutInFlight` guard unchanged at start of `_checkout()`.
- Sticky key assigned before entering try; same intent → same key for concurrent attempts (B5 serializes).
- `canStartCheckoutSubmit` tested (test 14).

---

## 10. clearCart / reset review — PASS

Successful checkout: `clearCheckoutKey(completedCartId)` then `clearCart()` (which also clears key). Completed sale key cannot survive into a new sale on the same numeric slot unless user bypasses success path (process-death limitation).

---

## 11. Conflict UX review — PASS

Message: `تعارض في عملية الدفع: المعاملات لا تطابق محاولة سابقة. غيّر العربة أو الدفع، أو امسح العربة ثم أعد المحاولة.`

Does not imply reopening dialog alone fixes conflict. No automatic key rotation on conflict.

---

## 12. B5 preservation review — PASS

No changes to `PosSaleService`, idempotency DAO/table, schema, or B5 test semantics. Different-key + same-fingerprint still allows two sales (B5 test 7) — unchanged; B27 prevents accidental third-key UI path for same intent.

---

## 13. Multi-cart review — PASS

Independent keys per slot (test 13). Switching tabs does not merge state. `clearCart` clears only active slot key.

---

## 14. Test quality review

**15 B27 tests** + regression suites. Mapping:

| Required invariant | Covered by |
|--------------------|------------|
| Fresh key | Test 1 |
| Same intent reuse | Tests 2, 3, 8 |
| Post-commit failure | Test 4 (state); **test 5 (B5 replay — stronger)** |
| Replay not duplicate | Test 5, 11 |
| Material cart/payment | Tests 6, 7 |
| clearCart / success clear | Tests 9, 10 |
| Conflict no rotation | Tests 12 + B5 conflict test |
| Two slots | Test 13 |
| In-flight | Test 14 |
| B5/B24/B25/B26 | Full regression run 79/79 |

**OPTIONAL:** No widget test that throws between `checkout()` return and `clearCart()`; unit + B5 replay tests adequately prove the fix.

---

## 15. Static / hygiene review — PASS

| Check | Result |
|-------|--------|
| B27 + B5 + B24 + B25 + B26 | **79/79** |
| `flutter analyze lib/features/pos` | **0 errors** |
| `git diff --check` | Clean |
| UTF-8 / no BOM (B27 Dart files) | Verified |
| Scope | B27 production + test + docs only (unrelated untracked docs/tools unchanged) |

---

## 16. Findings

| ID | Severity | Finding |
|----|----------|---------|
| F-01 | **PASS** | Primary post-commit retry scenario satisfied |
| F-02 | **PASS** | PaymentDialog has no UUID generation |
| F-03 | **PASS** | B5 contract and schema preserved |
| F-04 | **OPTIONAL** | Test 4 is in-memory only; test 5 provides persisted replay proof |
| F-05 | **OPTIONAL** | `PaymentInfo.idempotencyKey: ''` placeholder until orchestrator binds key |
| F-06 | **OPTIONAL** | Eager invalidation on cart edit after failed UI could allow new key if user restores identical cart (edge case) |
| F-07 | **PASS** | Process-death limitation documented; not a B27 blocker |

**BLOCKER:** none  
**SHOULD-FIX:** none  

---

## Final verdict

**REVIEW PASS**

Implementation is ready for Final Audit.