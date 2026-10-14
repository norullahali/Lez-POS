# B27 Implementation Report — POS Checkout Operation-Intent Idempotency

**Date:** 2026-10-14  
**Baseline HEAD:** `6d3d1b78f8f598adbc82b4b7536500e369d7cf96`  
**Schema:** 51 (unchanged)  
**Commit/push:** NOT performed

## Files changed

| File | Change |
|------|--------|
| `lib/features/pos/pos_checkout_idempotency.dart` | **New** — `PosCheckoutIdempotencyState`, slot state, in-flight helper |
| `lib/features/pos/providers/pos_provider.dart` | CartNotifier owns checkout idempotency map; `prepareCheckoutKey`, `computeCheckoutFingerprint`, invalidation hooks, `clearCart`/`removeCart` |
| `lib/features/pos/screens/pos_screen.dart` | `_checkout()` assigns sticky key before `processSale`; success clears key; conflict Arabic message |
| `lib/features/pos/screens/widgets/payment_dialog.dart` | Removed dialog-local UUID generation |
| `test/pos_checkout_idempotency_b27_test.dart` | **New** — 15 tests |
| `docs/b27_implementation_report.md` | This report |

## Architecture

- **Option C (approved):** per cart-slot `(fingerprintHash -> sticky UUID)` in `CartNotifier.checkoutIdempotency`.
- **Fingerprint:** sole authority `PosSaleFingerprint.compute` via `computeCheckoutFingerprint`.
- **B5:** unchanged; replay/conflict semantics preserved.

## Key lifecycle

- `prepareCheckoutKey` after payment confirm in `_checkout()`.
- Reuse when slot + fingerprint unchanged; reset when fingerprint changes.
- Cleared on successful checkout and `clearCart()` / `removeCart`.
- Retained on failure and on `PosSaleIdempotencyConflictException` (no auto-rotate).

## Multi-cart

Independent state per cart slot id (1–3). `switchCart` does not share keys.

## Conflict UX

Arabic snackbar instructs user to change cart/payment or clear cart; does not imply reopening dialog alone fixes conflict.

## Tests

| Suite | Result |
|-------|--------|
| B27 | 15/15 |
| B5 | 11/11 |
| B24 | 15/15 |
| B25 | 16/16 |
| B26 | 22/22 |
| **Combined** | **79/79** |

## Analyzer

`flutter analyze` on changed POS files: **0 errors**

## Hygiene

- `git diff --check`: clean
- Changed Dart files: UTF-8, no BOM

## Known limitation

Process death after DB commit before UI `clearCart()` may lose in-memory key; cart may restore from SharedPreferences — duplicate sale still possible without durable pending-checkout store (**out of B27 scope**).