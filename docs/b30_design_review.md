# B30 Design Review — Customer Manual Return UI Operation-Intent Idempotency

**Date:** 2026-10-19  
**Mode:** DESIGN ONLY (no production/test/schema/git changes)  
**Baseline HEAD:** `da030ab538015ee44661f17c2869ecb902dd3ac8`  
**Branch:** `main`  
**Schema:** 51  
**Discovery reference:** `docs/b30_discovery_report.md`  
**Discovery verdict:** B30 DISCOVERY READY FOR DESIGN REVIEW

---

## 1. Verified source architecture

### 1.1 Production entry and callers

| Layer | Location | Role |
|-------|----------|------|
| **Only production caller** | `lib/features/returns/screens/customer_returns_screen.dart` | `_submitManualReturn` → `manualReturnServiceProvider` |
| Service provider | `lib/features/returns/providers/manual_return_service_provider.dart` | `ManualReturnService(AppDatabase.instance)` |
| Canonical service | `lib/core/services/manual_return_service.dart` | `processManualReturn` |
| Fingerprint | `lib/core/services/manual_return_fingerprint.dart` | `ManualReturnFingerprint.compute` |
| Persistence | `lib/core/database/tables/customer_manual_return_idempotency_table.dart` | PK = `idempotencyKey` only (no unique on fingerprint) |
| DAO | `customer_manual_return_idempotency_dao.dart` (generated `.g.dart`) | lookup by key, insert seal |

**Grep confirmation:** `processManualReturn` is invoked only from `customer_returns_screen.dart` under `lib/`. No other production UI path posts manual returns.

### 1.2 UI flow today

1. User taps action → `_showCustomerReturnDialog()` (L330).
2. **`_clearManualReturnAttempt()` runs at dialog open (L331)** — clears `_manualReturnIdempotencyKey` and `_pendingManualReturnPayload`.
3. `showDialog` collects `ManualReturnPayload` (product, qty, reason, `unitPrice: 0.0`, `userId` from auth).
4. Dialog closes → `_submitManualReturn(payload)` (L433).
5. Submit guard: `_manualReturnSubmitting` (L105).
6. Payload change: if `_pendingManualReturnPayload` does not `matches` new payload → `_clearManualReturnAttempt()` (L107–109).
7. Key mint: `_manualReturnIdempotencyKey ??= _manualReturnUuid.v4()` (L112).
8. Service call without `approvedByUserId` (defaults null) (L117–124).

### 1.3 UUID generation and clearing (verified)

| Event | Current behavior | Source |
|-------|------------------|--------|
| New key mint | `??=` on `_manualReturnIdempotencyKey` per submit attempt after payload binding | L112 |
| Dialog open | **Full clear** (key + pending payload) | L331 |
| Material payload change (`ManualReturnPayload.matches`) | Clear attempt | L107–109 |
| Service success | **Clear attempt** (key discarded) | L126 |
| `ManualReturnIdempotencyConflictException` | **Clear attempt** | L138–139 |
| Generic failure | Key **retained** | catch L150–158 (no clear) |
| Quick return path | Separate keys (out of B30 scope) | L165+ |

**Discovery claim confirmed:** Success and conflict clear the UUID; different keys with identical service parameters can create two returns (`b10` test 14).

**Additional finding (not in discovery):** Dialog open (L331) clears pending state **before** every new manual-return dialog, so even a failed submit’s sticky `_manualReturnIdempotencyKey` is wiped on reopen. Cross-dialog retry currently always mints a new key unless the user retries without reopening (impossible — dialog already closed).

### 1.4 Payload equality vs service fingerprint

`ManualReturnPayload.matches` compares raw `reason`, `quantity`, `unitPrice`, `productId`, `userId` (L36–41). It does **not** use `ManualReturnFingerprint` normalization.

Service always:

- `normalizeReason(reason)` → trim  
- `roundAmount` on quantity and unitPrice (6 dp)  
- `approvedByUserId` from parameter (UI never passes → always null in production)

UI always sends `unitPrice: 0.0` (L419). No manager-approval path on manual return (unlike quick return).

### 1.5 Service replay / conflict contract (B10)

Inside **one** `db.transaction` per attempt (`manual_return_service.dart` L42–112):

1. Lookup `customer_manual_return_idempotency` by **idempotencyKey**.
2. If row exists: same `fingerprintHash` → **replay** (`idempotentReplay: true`); different hash → **`ManualReturnIdempotencyConflictException`**.
3. Else: insert return + stock via `returnsDao.saveCustomerReturnInTransaction`, optional `preSealHook`, insert idempotency row (seal).
4. Seal race: retry loop (max 8) on unique key violation.

**Transaction boundary:** One logical operation per key is atomic (return row + stock + seal). **Cross-key** duplicate intents are **not** prevented at service layer (`b10` test 14).

### 1.6 Reference implementations (B27 / B28 / B29)

| Pattern | Owner | Map key | Clear on success | Clear on conflict | Post-commit failure |
|---------|-------|---------|------------------|-------------------|---------------------|
| B27 checkout | `CartNotifier.checkoutIdempotency` | cart slot + fingerprint | `clearCheckoutKey` after confirmed checkout | N/A (conflict at service) | Sticky until success clear |
| B28 customer refund | `CustomerRefundSettlementIdempotencyState` on notifier | fingerprint hash | `clearSettlementKey(fp)` after success path | Key retained on failure | B29 SF-01: refresh throw → key retained |
| B29 supplier refund | Same as B28 | fingerprint hash | After refresh hook | SF-04: key retained | SF-01/SF-02 tests |

B30 should align with **B28/B29**, not with current manual-return screen clearing.

---

## 2. Confirmed vulnerability

**Class:** UI operation-intent idempotency gap (same family as pre-B28/B29 refund settlement).

**Mechanism:**

1. `ManualReturnService` is authoritative and replay-safe **per idempotency key**.
2. UI discards the key on success (L126) and on conflict (L139), and on every dialog open (L331).
3. Service permits two keys with identical fingerprint → two return rows and double stock restoration (`customer_manual_return_idempotency_b10_test.dart` test **14**).

**Credible production scenario:**

1. User submits manual return; service commits.
2. `_clearManualReturnAttempt()` runs immediately (L126) — key lost **before** user necessarily sees success feedback.
3. User opens “مرتجع عميل جديد” again with the same product/qty/reason.
4. New UUID → second committed return.

**Severity:** Material inventory / return-history integrity (P1 per discovery); not a service txn bug.

---

## 3. Option comparison

### Option A — Screen-owned sticky `fingerprintHash → UUID` map (discovery recommendation)

Use existing `ManualReturnFingerprint.compute` with **exact** arguments passed to `processManualReturn`. Helper mirrors `CustomerRefundSettlementIdempotencyState` / `SupplierRefundSettlementIdempotencyState`.

| Criterion | Assessment |
|-----------|------------|
| Correctness | Closes cross-retry/reopen duplicate for same unresolved intent |
| Retry / reopen | Same fingerprint → same key until explicit success clear |
| Legitimate consecutive identical returns | **Supported:** `clearReturnKey(fingerprint)` only after **confirmed** success → next submit mints new UUID via `putIfAbsent` |
| Payload changes | New fingerprint → new map entry; optional cleanup of stale entries not required for correctness |
| Post-commit ambiguity | **Requires** ordering: service commit → post-success invalidation → clear map **only if** full success path completes; on refresh/invalidate failure, **retain** key (B29 SF-01) |
| Concurrency | Same-key races handled by B10; UI `_manualReturnSubmitting` blocks double flight |
| Migration | None |
| Regression | Low if B10 tests untouched; add B30 UI tests |
| Scope | Small: 1 helper file + `customer_returns_screen.dart` + new test file |
| B27/B28/B29 consistency | **High** |

### Option B — Service-level rejection of duplicate business fingerprint

Reject second operation when fingerprint already exists in idempotency table (lookup by hash).

| Criterion | Assessment |
|-----------|------------|
| Correctness | Blocks accidental duplicate **and** intentional second identical return |
| Legitimate consecutive returns | **Broken** unless fingerprint encodes a per-operation nonce (which would defeat cross-retry replay) |
| Migration | Likely index / query changes on `fingerprint_hash` |
| Regression | High — changes B10 contract test 14 semantics |
| Scope | Service + DAO + tests |

**Not recommended** for B30.

### Option C — Durable pending-operation storage (SharedPreferences / Drift)

Survives process death.

| Criterion | Assessment |
|-----------|------------|
| Correctness | Highest durability |
| Scope | Large; exceeds B27/B28/B29 accepted non-goals |
| Requirement | No source requirement for kill-after-commit parity on manual return |

**Deferred** unless product mandates process-death replay (non-goal for B30).

### Recommendation

**Option A** — smallest safe change, consistent with B28/B29, no schema change, preserves intentional back-to-back identical returns via **success-scoped** `clearReturnKey`.

---

## 4. Fingerprint contract (canonical)

**Single definition:** `ManualReturnFingerprint.compute` in `lib/core/services/manual_return_fingerprint.dart` — **do not** add a second UI-only hash.

At submit time, compute:

```dart
ManualReturnFingerprint.compute(
  productId: payload.productId,
  quantity: ManualReturnFingerprint.roundAmount(payload.quantity),
  unitPrice: ManualReturnFingerprint.roundAmount(payload.unitPrice),
  reason: ManualReturnFingerprint.normalizeReason(payload.reason),
  userId: payload.userId,
  approvedByUserId: null, // until UI passes approver; must match service call
);
```

**Included fields (JSON payload keys):**

| Field | Normalization | Production today |
|-------|---------------|------------------|
| `productId` | exact int | From dialog |
| `quantity` | `roundAmount` (6 dp) | Parsed from qty field |
| `unitPrice` | `roundAmount` (6 dp) | Always `0.0` |
| `reason` | `normalizeReason` (trim) | `noteCtrl.text.trim()` |
| `userId` | nullable int | `currentUser?.id` |
| `approvedByUserId` | nullable int | **Always null** (not passed to service) |

**Material intent change:** Any change that alters the computed fingerprint after normalization → new sticky slot (new UUID on first submit).

**Non-material:** Widget rebuilds, dialog re-layout, loading overlay — no fingerprint recompute side effects if submit parameters unchanged.

**Payload equality migration:** Replace or supplement `ManualReturnPayload.matches` for key invalidation with fingerprint inequality (or keep matches as fast path but **submit must use fingerprint** as source of truth). If raw `matches` and fingerprint ever disagree (e.g. whitespace-only reason), **fingerprint wins** for service alignment.

**Future:** If manual return gains `approvedByUserId`, include in both service call and fingerprint (same as B10 table columns).

---

## 5. State ownership

**Chosen owner:** `CustomerManualReturnIdempotencyState` (new helper) held as a **private field** on `_CustomerReturnsScreenState`, mirroring B24 on `PosScreen` and B28 on the refund notifier.

**Why not Riverpod notifier:** Manual return orchestration lives entirely on the screen today; no existing notifier. Extracting a notifier is optional and **out of scope**.

**Why not only `_manualReturnIdempotencyKey`:** Single scalar cannot hold multiple unresolved fingerprints or survive the correct lifecycle; map keyed by fingerprint hash matches B28/B29.

**Lifetime:** In-memory for the life of the `CustomerReturnsScreen` state object. **No** SharedPreferences. Process death may lose sticky keys (accepted P2, same as B27/B28/B29).

**Reset semantics:**

| Action | Clears visible UI / pending | Clears sticky map |
|--------|----------------------------|-------------------|
| Dialog cancel | N/A | **No** |
| Dialog open (`_showCustomerReturnDialog`) | **Must not** clear sticky map (remove L331 clear of keys) | **No** |
| Submit success (full path) | Optional pending clear | **`clearReturnKey(fingerprint)`** |
| Submit failure (non-conflict) | — | **No** |
| Conflict | — | **No** (change from today L139) |
| User navigates away from screen | State disposed | Map discarded (acceptable) |

**Genuinely new business intent after success:** Success path clears fingerprint entry → next `prepareReturnKey` allocates fresh UUID even for identical fields (T11).

**Unresolved intent:** Fingerprint entry remains → reopen dialog and re-submit same fields → same UUID → service replay.

---

## 6. Key lifecycle specification

| ID | Scenario | Required behavior |
|----|----------|-------------------|
| **A** | First submission | `prepareReturnKey(fingerprint, generateUuid)` → K1 stored in map |
| **B** | Double submit in flight | `_manualReturnSubmitting` returns early; at most one in-flight service call (T9) |
| **C** | Service success (fresh commit) | Run post-success invalidation/snackbar; then `clearReturnKey(fingerprint)` |
| **D** | Service replay (same K1 + fp) | UI may treat as success; no second return row |
| **E** | Exception before commit | Map retains K1; retry reuses K1 |
| **F** | Conflict | Show error; **retain** K1 (do not call `_clearManualReturnAttempt` for map); user must change payload or escalate |
| **G** | Post-commit refresh/invalidation failure | **Retain** K1 in map; surface failure; retry replays (mirror B29 SF-01) |
| **H** | Dialog reopen (same screen) | Same fp → K1 via map; **remove** L331 key clear |
| **I** | Material payload change | New fp → new map entry → new UUID on first submit to that fp |
| **J** | Non-material UI rebuild | No map change |
| **K** | Intentional new return after confirmed success | Map entry cleared in (C) → new UUID for same fp allowed |
| **L** | Two independent intents (different fp) | Independent map entries; no cross-overwrite |

**Critical invariant:** One logical manual-return intent (one fingerprint) reuses one UUID until success clears that fingerprint slot.

**Distinguishing unresolved vs intentional new:** **Success completion** is the only automatic clear of the fingerprint slot. No automatic clear on dialog open.

---

## 7. Post-commit ambiguity and intentional new return

### 7.1 Ambiguity path (must hold)

1. UI binds K1 = `prepareReturnKey(fp)`.
2. `processManualReturn` commits return + stock + seal.
3. Post-success `ref.invalidate(...)` or snackbar path throws / user sees failure.
4. Map **still** holds K1 (do **not** clear before invalidation succeeds).
5. User reopens dialog, same fields → fp unchanged → K1.
6. Service replay → one return row, one stock delta.

**Implementation note:** Today L126 clears key **immediately** after service; B30 **must** defer `clearReturnKey` until after post-success work (or only clear when treating outcome as confirmed success), matching B29 ordering.

### 7.2 Intentional identical new return (must hold)

1. K1 succeeds; full success path runs; `clearReturnKey(fp)`.
2. User starts new manual return with identical product/qty/reason/user.
3. `prepareReturnKey` → new K2 (`putIfAbsent` misses cleared entry).
4. Service creates second return (legitimate business case).

Both cases are satisfied by **fingerprint-scoped clear only on confirmed success**, not on dialog open.

---

## 8. Concurrency behavior

- **UI:** `_manualReturnSubmitting` serializes submit entry (same as today).
- **Service:** B10 same-key concurrent transactions → one commit + replays (existing tests).
- **Different keys, same fingerprint:** Still possible across two app instances or future multi-window; **out of B30 scope** (same residual as B5/B10 test 14). UI map is single-process.

---

## 9. Test matrix

Use `Completer` / barriers for ordering (B29 T16, SF-01). **No** `Future.delayed` as proof.

| ID | Description | Type | Key assertion |
|----|-------------|------|---------------|
| T1 | Fingerprint deterministic | Unit | Same inputs → same hash |
| T2 | Material payload change → different fp | Unit | Different hash |
| T3 | Normalized equivalent reason/qty → same fp | Unit | Trim / 6dp |
| T4 | Dialog reopen / reset UI preserves key for unresolved fp | Integration | Same K after simulated reopen |
| T5 | Pre-commit failure retains K | Integration | Retry same K |
| T6 | Post-commit invalidate failure retains K | Integration | Override invalidate to throw; map holds K |
| T7 | Retry after (6) replays; one return row | Service + integration | `idempotentReplay` / row count |
| T8 | Conflict retains K without rotation | Integration | SF-04 analogue |
| T9 | Double submit one service call | Integration | Completer gate |
| T10 | Success clears fp slot | Integration | `keyForFingerprint` null after success |
| T11 | After (10), identical fields get new K | Integration | Keys differ |
| T12 | Two fps → two keys | Unit / integration | Map size 2 |
| T13 | Payload change invalidates prior sticky slot usage | Integration | New fp → new K; old fp unchanged if still pending |
| T14 | B10 suite unchanged | CI | No edits to existing B10 expectations |

**Suggested file:** `test/customer_manual_return_idempotency_b30_test.dart` (helper state tests + screen/widget integration with provider overrides).

Extract submit orchestration to a testable method or use widget test on `CustomerReturnsScreen` with mocked `ManualReturnService` (B29 pattern).

---

## 10. Scope and migration

### 10.1 Schema / migration

**None.** Reuse `customer_manual_return_idempotency` with existing keys.

### 10.2 Expected file touch list (implementation phase)

| File | Change |
|------|--------|
| `lib/features/returns/customer_manual_return_idempotency.dart` | **New** — `CustomerManualReturnIdempotencyState` (`prepareReturnKey`, `clearReturnKey`, `@visibleForTesting` accessors) |
| `lib/features/returns/screens/customer_returns_screen.dart` | Submit path, lifecycle fixes (L331, L126–139 ordering), fingerprint at submit |
| `test/customer_manual_return_idempotency_b30_test.dart` | **New** — T1–T13 |

### 10.3 Explicitly out of scope

- `ManualReturnService`, DAO, table, schema
- Quick return (`_submitQuickReturn`) — future milestone
- Supplier / invoice return paths
- Durable cross-process storage
- Changing B10 service test 14 semantics

---

## 11. Risks and non-goals

| Risk | Mitigation |
|------|------------|
| L331 dialog-open clear regresses sticky behavior | **Mandatory:** remove map clear on dialog open |
| Early clear after service (L126) | Defer `clearReturnKey` to end of success path |
| Conflict clears key (L139) | Retain key; align message with B29 SF-04 |
| `matches` vs fingerprint drift | Submit uses fingerprint only |
| Memory: many abandoned fps | Bounded by rare pending intents; optional prune on success only |
| Process death | Accepted P2 (document in implementation report) |

**Non-goals:** Service-level fingerprint uniqueness; quick-return parity; multi-device sync.

---

## 12. Implementation conditions (before merge)

These are **resolved design requirements**, not open questions:

1. **Remove** `_clearManualReturnAttempt()` on dialog open (L331) for sticky map purposes — or restrict that call to pending display state only, **never** the fingerprint map.
2. **Defer** `clearReturnKey(fingerprint)` until after post-success invalidation/snackbar completes successfully; on failure, retain key (B29 SF-01).
3. **On conflict**, retain sticky key (do not mirror current L138–139 full clear).
4. **Compute fingerprint** with the same normalization and parameters as `processManualReturn` (including `approvedByUserId: null` until UI sends it).

---

## 13. Final recommendation

Approve **Option A**: screen-owned `CustomerManualReturnIdempotencyState` using **`ManualReturnFingerprint`** as the sole intent definition, with lifecycle aligned to **B28/B29** (success-only clear, conflict retention, post-commit failure retention).

Quick return remains a separate milestone.

---

## Final verdict

**B30 DESIGN APPROVED WITH CONDITIONS**

Conditions are listed in §12; they follow directly from verified source lines in `customer_returns_screen.dart` and must be implemented as specified before B30 can close.
