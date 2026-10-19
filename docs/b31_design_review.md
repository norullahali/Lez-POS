# B31 Design Review — Customer Quick Return UI Operation-Intent Idempotency

**Date:** 2026-10-19
**Mode:** DESIGN ONLY (no production/test/schema/git changes)
**Baseline HEAD:** `336dd3f1df1742615c9da278f6d012bce8cc9398`
**Branch:** `main` (HEAD = origin/main)
**Schema:** 51
**Discovery reference:** `docs/b31_discovery_report.md`
**Architectural reference:** `docs/b30_design_review.md`, B30 implementation (`customer_manual_return_idempotency.dart`)

---

## 1. Baseline verification

| Check | Result |
|-------|--------|
| Branch | `main` |
| HEAD | `336dd3f1df1742615c9da278f6d012bce8cc9398` |
| origin/main | Matches HEAD |
| Schema | **51** (`lib/core/database/app_database.dart`) |
| Tracked modifications | **None** (unrelated untracked docs/tools only) |
| B30 manual-return path | Closed at `336dd3f` — **out of B31 scope** |

---

## 2. Source-trace findings

### 2.1 UI flow (verified)

**Entry:** `CustomerReturnsScreen` → `_showQuickReturnDialog()` (`customer_returns_screen.dart` L438–584).

1. **`_clearQuickReturnAttempt()` at dialog open (L439)** — clears `_quickReturnIdempotencyKey` and `_pendingQuickReturnPayload` before every dialog.
2. Dialog collects `QuickReturnPayload`: `productId`, `quantity`, `refundAmount = productPrice * qty`, `reason` (dropdown), `userId` (L546–555).
3. **Manager approval (conditional):** After dialog closes, if `refundAmount > currentUser.refundLimit` and user is not admin (`roleId != 1`), `ManagerApprovalDialog` runs (L566–581). On cancel → **return without submit**. On success → `approvedByUserId = approver.id`.
4. **`_submitQuickReturn(payload, approvedByUserId: …)`** (L174–237):
   - Guard `_quickReturnSubmitting`.
   - If pending payload `matches` differs → `_clearQuickReturnAttempt()` (L180–183).
   - `_quickReturnIdempotencyKey ??= _quickReturnUuid.v4()` (L185).
   - Calls `PosSaleService.processQuickReturn` with key + payload fields + `approvedByUserId`.
   - **Success:** `_clearQuickReturnAttempt()` then invalidations (L200–203).
   - **Conflict:** `_clearQuickReturnAttempt()` (L213).
   - **Generic failure:** key **retained** (no clear in catch L224–232).
5. Dialog save disabled when `_quickReturnSubmitting` (L534) — not a shared runner `inFlight` yet.

**Manual-return path on same screen** uses `CustomerManualReturnSubmitRunner` (B30) — **separate** from quick-return scalars.

### 2.2 Service contract (verified)

`PosSaleService.processQuickReturn` (`pos_sale_service.dart` L315–507):

- Normalizes: `normalizeReason`, `roundAmount(quantity)`, `roundAmount(refundAmount)`.
- Fingerprint: `QuickReturnFingerprint.compute(productId, quantity, refundAmount, reason, userId, approvedByUserId)` (L329–336).
- Lookup by **idempotencyKey**; same hash → **replay** (no stock/return mutation); different hash → **`QuickReturnIdempotencyConflictException`** (L341–346).
- Fresh commit: insert `customer_returns`, `customer_return_items`, stock ledger + `current_stock`, audit, `logsTable` RETURN_WITHOUT_INVOICE, seal row in **`customer_quick_return_idempotency`** (L454–463).
- **No POS session id** in quick-return transaction (verified — session appears only on sale path elsewhere in file).

### 2.3 Canonical fingerprint (`quick_return_fingerprint.dart`)

JSON keys: `approvedByUserId`, `productId`, `quantity` (6 dp), `reason` (trim), `refundAmount` (6 dp), `userId` (**required int**).

**Not in fingerprint:** session, invoice, dialog-only fields.

### 2.4 Persistence

- Table: `customer_quick_return_idempotency` (v41 migration in `app_database.dart`).
- DAO: `customerQuickReturnIdempotencyDao` — PK idempotency key; stores fingerprint hash and payload snapshot.

### 2.5 B9 tests (relevant)

- **Service:** test **15** — different keys + same logical params → **two returns** (proves UI must stabilize key).
- **UI lifecycle:** **26** — two successes with identical fields → **two keys** (compatible with B31 **after** slot clear on success).
- **UI 27** — conflict then retry → expects **new key** — **obsolete** under sticky retention (same as B10/27 after B30).
- **UI 28** — cancel dialog then submit → one call (no key bound until submit — remains compatible).
- **UI 24** — double-submit one service call (must remain passing).
- Schema pins **21/22/29 analog** in B9 at lines 603/608/615 (`schemaVersion == 50`) — pre-existing hygiene, not B31 scope.

---

## 3. Design options

### Option A — Dedicated quick-return sticky map + submit runner (B30 analogue)

New `customer_quick_return_idempotency.dart`:

- `computeQuickReturnIntentFingerprint` → delegates to `QuickReturnFingerprint.compute` with **identical** normalization as service.
- `CustomerQuickReturnIdempotencyState` — `fingerprintHash → UUID`.
- `CustomerQuickReturnSubmitRunner` — same outcome enum pattern as B30 (`success`, `postSuccessRefreshFailed`, `idempotencyConflict`, `serviceFailure`, `skippedInFlight`).
- Screen: `_quickReturnSubmitRunner` field; wire `_submitQuickReturn` only; **remove** scalar key/pending clear-on-open/success/conflict for the map.

| Criterion | Rating |
|-----------|--------|
| Financial correctness | **High** — replay + post-commit ambiguity aligned with B30 |
| Retry after refresh failure | **High** |
| Conflict retention | **High** |
| Intentional identical new return | **High** (clear slot after full success) |
| Double-submit | **High** (`inFlight`) |
| Manager approval | **High** if intent built **after** approval with final `approvedByUserId` |
| Refund amount | **High** — must pass same `refundAmount` to fingerprint and service |
| Complexity | Medium — ~140 lines parallel to B30 |
| Consistency B27–B30 | **Best** |
| Testability | **High** (copy B30 matrix) |

### Option B — Minimal refactor of existing scalars

Keep `_quickReturnIdempotencyKey` / `_pendingQuickReturnPayload`; adjust clear rules only.

| Criterion | Rating |
|-----------|--------|
| Correctness | Medium — easy to miss post-success ordering or multi-fingerprint cases |
| Multi unresolved intents | **Poor** (single scalar) |
| Consistency | **Low** vs B30 |

### Option C — Service-level unique fingerprint index

Reject for B31 (same rationale as B30 Option B): migration risk, blocks legitimate distinct keys, out of discovery scope.

### Recommendation

**Option A** — with **separate** runner/state from manual return (do **not** share one map between manual and quick fingerprints).

---

## 4. Recommended design (Option A)

### 4.1 Operation intent

One **quick-return business intent** = one canonical fingerprint hash derived from the exact parameters passed to `processQuickReturn` at submit time:

- `productId`
- `quantity` (normalized)
- `refundAmount` (normalized)
- `reason` (normalized)
- `userId`
- `approvedByUserId` (null when approval not required; set when manager approved)

**Intent is finalized only after** the manager-approval branch completes (approval granted or skipped). If approval dialog is cancelled, **no** `submit()` call and **no** key binding.

### 4.2 Fingerprint contract

**Single definition:** `QuickReturnFingerprint.compute` — no competing UI hash.

Helper:

```dart
computeQuickReturnIntentFingerprint(
  productId, quantity, refundAmount, reason,
  userId, approvedByUserId,
) => QuickReturnFingerprint.compute(
  productId: productId,
  quantity: QuickReturnFingerprint.roundAmount(quantity),
  refundAmount: QuickReturnFingerprint.roundAmount(refundAmount),
  reason: QuickReturnFingerprint.normalizeReason(reason),
  userId: userId,
  approvedByUserId: approvedByUserId,
);
```

**Material change:** any field above changes after normalization → new fingerprint → new sticky slot.

**Refund amount:** UI computes `productPrice * qty` (L546). That **computed** value must be used for both fingerprint and service call (not recomputed differently on retry).

**Session:** Not part of fingerprint (service does not include it).

### 4.3 State ownership

- **Owner:** `CustomerQuickReturnSubmitRunner` + `CustomerQuickReturnIdempotencyState` as private field on `_CustomerReturnsScreenState` (**distinct** from `_manualReturnSubmitRunner`).
- **Lifetime:** In-memory for screen state; process death loses map (accepted P2, same as B30).

### 4.4 Sticky key lifecycle

| Action | Sticky map |
|--------|------------|
| Open quick-return dialog | **Do not clear** (remove L439 clear of keys) |
| Dialog cancel (no submit) | **No** |
| Manager approval cancelled | **No** submit |
| First submit for fingerprint | `prepareReturnKey` → K1 |
| Double submit in flight | `skippedInFlight`; one service call |
| Service success + refresh OK | `clearReturnKey(fingerprint)` only |
| Pre-commit / service failure | **Retain** |
| Idempotency conflict | **Retain** (no auto rotation) |
| Post-commit refresh failure | **Retain**; user message; retry replays |
| Intentional new return after full success | Slot cleared → new UUID (same fields allowed) |
| Navigate away from screen | Map discarded |

**Remove:** `_clearQuickReturnAttempt()` on success/conflict for **map** purposes; may delete helper entirely if pending payload matching is replaced by fingerprint (preferred: **fingerprint is source of truth**, drop `_pendingQuickReturnPayload` matching like B30 dropped manual pending key pattern).

### 4.5 Post-success ordering (mandatory)

Mirror B30/B29:

1. `invokeService(K1)` commits return + stock + seal.
2. `postSuccessRefresh()` — same invalidations as today (customer returns, products, return analytics).
3. **Only if refresh succeeds** → `clearReturnKey(fingerprint)`.
4. If refresh throws → `postSuccessRefreshFailed` snackbar; **key retained**.

### 4.6 In-flight guard and UI

- Runner `_inFlight` authoritative for concurrent submits.
- Quick dialog confirm button: disable when `_quickReturnSubmitRunner.inFlight` (replace or supplement `_quickReturnSubmitting`).
- `skippedInFlight`: silent return (same as B30) or optional snackbar (P3).

### 4.7 Separation from manual return

- Do **not** merge quick and manual sticky maps.
- Do **not** change `CustomerManualReturnSubmitRunner` or manual dialog behavior in B31.

---

## 5. Lifecycle / state transition table

| ID | Scenario | Required behavior |
|----|----------|-------------------|
| A | First submit | `prepareReturnKey(fp)` → K1 |
| B | Double submit | At most one in-flight `processQuickReturn` |
| C | Success + refresh OK | Clear **this** fp slot only |
| D | Replay same K1 + fp | No second return/stock |
| E | Pre-commit failure | Retain K1 |
| F | Conflict | Retain K1 |
| G | Post-commit refresh failure | Retain K1; retry replays |
| H | Dialog reopen | Same fp → K1 |
| I | Material fp change | New slot / new UUID |
| J | Success then identical new return | New K2 after slot clear |
| K | Two different fps pending | Independent keys (T10 analogue) |
| L | Approval changes `approvedByUserId` | **Different fp** → different slot |

---

## 6. Test matrix (B31)

Use `AppDatabase.test` + real `PosSaleService` for financial cases; Completer for concurrency; **no** `Future.delayed` as concurrency proof.

| ID | Scenario | Type | Key assertion |
|----|----------|------|---------------|
| T1 | Fingerprint deterministic | Unit | Same inputs → same hash |
| T2 | Material change (qty/refund/product/reason/user) | Unit | Different hash |
| T3 | Normalized equivalence (trim reason, 6 dp) | Unit | Same hash |
| T4 | Dialog reopen simulation | Integration | Same K after `prepareReturnKey` twice |
| T5 | Pre-commit failure retains K | Integration | Real service on retry; one return |
| T6/T7 | Post-commit refresh failure then replay | Integration | **1** return row, **1** stock delta |
| T8 | Real same-key different-payload conflict | Integration | Conflict outcome; **1** return; stock unchanged; K retained |
| T8s | Synthetic conflict (optional) | Integration | Runner retains K (fast path) |
| T9 | Double submit | Integration | Completer; one service call |
| T10 | Success clears only completed fp slot | Integration | Two fps; one submit success |
| T11 | Intentional identical second return | Integration | Two returns, two keys (`mintSeq`), stock +2 |
| T12 | Independent fps | Unit/state | Two map entries |
| T13 | Payload/fp change → different K | Integration | Different keys |
| T14 | `approvedByUserId` in fingerprint | Unit | null vs id → different hash; service parity test when approval path simulated |

**B9 regression:** Run service idempotency group (incl. test 15); **do not** change B9 service assertions. Expect **B9 UI test 27** to fail until a future B9 UI hygiene pass (document, do not weaken).

---

## 7. Scope boundaries

### In scope (expected files)

| Path | Change |
|------|--------|
| `lib/features/returns/customer_quick_return_idempotency.dart` | **Add** |
| `lib/features/returns/screens/customer_returns_screen.dart` | **Modify** — quick path only |
| `test/customer_quick_return_idempotency_b31_test.dart` | **Add** |
| `docs/b31_implementation_report.md` | **Add** (implementation phase) |

### Out of scope

- `PosSaleService`, `QuickReturnFingerprint`, DAO/table/migrations
- Manual return runner (B30)
- Supplier / invoice-linked returns
- POS session guards
- B9/B10 test edits (unless separate hygiene milestone)
- SharedPreferences / durable pending ops
- Payment workflows

### Schema

**None required** for Option A.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Approval after dialog changes fp | Build `QuickReturnSubmitIntent` **after** approval branch |
| `refundAmount` drift vs qty×price | Single payload value into fingerprint + service |
| B9 UI 27 failure | Expected; classify as contract change |
| Legitimate back-to-back quick returns | Clear slot only on full success (T11) |
| Cross-talk manual vs quick | Separate runner instances/maps |

---

## 9. Implementation plan (high level)

1. Add `customer_quick_return_idempotency.dart` (mirror B30 structure; quick types/outcomes).
2. Refactor `_submitQuickReturn` to runner; move invalidations to `postSuccessRefresh`.
3. Remove `_clearQuickReturnAttempt()` at `_showQuickReturnDialog` start; remove map clear on success/conflict.
4. Wire dialog button to `_quickReturnSubmitRunner.inFlight`.
5. Add B31 test file (matrix above).
6. Run B31 suite, targeted B9 service tests, analyzer, schema 51 check.

---

## 10. Unresolved questions

1. **Widget-level** screen test for post-refresh failure (optional; B30 used runner + DB).
2. **Snackbar** for `skippedInFlight` (optional UX).
3. Whether to remove `QuickReturnPayload.matches` / `_pendingQuickReturnPayload` entirely in implementation (recommended: yes, fingerprint-only).

---

## 11. Conditions for approval

1. Implement **separate** quick-return runner/state (not shared with manual).
2. **Remove** dialog-open sticky clear (L439).
3. **Defer** `clearReturnKey` until after successful post-success refresh.
4. **Retain** key on conflict and post-commit refresh failure.
5. Include **`approvedByUserId`** in intent when passed to service.
6. **No** service/schema changes in B31 unless design review during implementation proves Option A insufficient (then **stop** and re-review).

---

## 12. Final verdict

**B31 DESIGN APPROVED WITH CONDITIONS**

(Conditions listed in §11.)

Design Review complete — **no implementation** in this task.
