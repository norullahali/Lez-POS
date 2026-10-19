# B30 Review Pass — Customer Manual Return UI Operation-Intent Idempotency

**Date:** 2026-10-19  
**Mode:** READ-ONLY (no code/test/schema/git changes)  
**Baseline HEAD:** `da030ab538015ee44661f17c2869ecb902dd3ac8`  
**Schema:** 51  
**References:** `docs/b30_design_review.md`, `docs/b30_implementation_report.md`

---

## 1. Review scope

Independent verification of B30 against the approved design:

- Production: `lib/features/returns/customer_manual_return_idempotency.dart`, manual-return path in `lib/features/returns/screens/customer_returns_screen.dart`
- Tests: `test/customer_manual_return_idempotency_b30_test.dart` (13 cases)
- Unchanged backend: `ManualReturnService`, `ManualReturnFingerprint`, `customer_manual_return_idempotency` DAO/table
- Regression context: B10 suite, B28/B29 sticky-key patterns

Implementation report used as pointers only; conclusions below are from source and test execution.

---

## 2. Source verification

### 2.1 Architecture

| Layer | Finding |
|-------|---------|
| **Fingerprint** | `computeManualReturnIntentFingerprint` delegates to `ManualReturnFingerprint.compute` after the same `roundAmount` / `normalizeReason` steps the service applies (`customer_manual_return_idempotency.dart:18–25`). |
| **Sticky map** | `CustomerManualReturnIdempotencyState` — `putIfAbsent` per `fingerprintHash` (`:35–39`); `clearReturnKey` removes one slot (`:42–44`). |
| **Orchestration** | `CustomerManualReturnSubmitRunner.submit` binds key, calls service, then refresh, then clear (`:101–137`). |
| **Screen** | Single `_manualReturnSubmitRunner` field on `_CustomerReturnsScreenState` (`customer_returns_screen.dart:95–96`); `_showCustomerReturnDialog` does **not** clear the map (`:334+`). |
| **Quick return** | Separate `_quickReturnIdempotencyKey` / `_clearQuickReturnAttempt` unchanged (`:169+`, `:438+`). |

### 2.2 Git / scope boundary

`git diff da030ab… --stat`: only tracked change is `customer_returns_screen.dart` (46 insertions, 44 deletions). New files are untracked: `customer_manual_return_idempotency.dart`, B30 test, docs.

`git diff da030ab… -- lib/core/services/manual_return_service.dart lib/core/services/manual_return_fingerprint.dart lib/core/database/`: **empty**.

---

## 3. Fingerprint contract

**Conformance: yes.**

Service fingerprint (`manual_return_service.dart:28–38`):

- `normalizeReason(reason)`, `roundAmount(quantity)`, `roundAmount(unitPrice)`
- `ManualReturnFingerprint.compute(..., userId, approvedByUserId)`

UI intent + service call (`customer_returns_screen.dart:98–120`):

- `ManualReturnSubmitIntent` omits `approvedByUserId` → null in fingerprint (matches production UI never passing `approvedByUserId` to `processManualReturn`)
- Service invoked with the same raw `productId`, `quantity`, `unitPrice`, `reason`, `userId` as the intent
- Dialog always sends `unitPrice: 0.0` (`:418–424`)

B30 tests T1–T3 verify determinism, material change, and normalized equivalence against `computeManualReturnIntentFingerprint`.

No competing fingerprint algorithm was introduced.

---

## 4. Sticky key lifecycle

**Conformance: yes** (design §5–6, lifecycle A–L).

| Design requirement | Implementation evidence |
|--------------------|-------------------------|
| Sticky `fingerprintHash → UUID` | `prepareReturnKey` / map (`customer_manual_return_idempotency.dart:31–40`) |
| Survives dialog reopen | No map reset in `_showCustomerReturnDialog`; runner lifetime = screen state |
| No clear on dialog open | Pre-B30 `_clearManualReturnAttempt` at dialog open removed (per diff vs baseline) |
| Clear only after full success | `clearReturnKey` only after `postSuccessRefresh` succeeds (`:122–129`) |
| Retain on pre-commit failure | Catch returns `serviceFailure`; no clear (`:132–133`) |
| Retain on conflict | `ManualReturnIdempotencyConflictException` branch; no clear (`:130–131`) |
| Retain on post-commit refresh failure | Inner catch returns `postSuccessRefreshFailed`; no clear (`:122–126`) |
| Per-fingerprint clear | `clearReturnKey(fingerprintHash)` not map-wide |
| Intentional new identical return | After success clear, `putIfAbsent` mints again (T11) |

Screen `switch (outcome)` (`customer_returns_screen.dart:133–166`) shows snackbars only; **no** `clearReturnKey` or runner reset on any outcome, including conflict and refresh failure.

---

## 5. Post-commit ambiguity (financial safety)

**Conformance: yes. Not a blocker.**

Examined `CustomerManualReturnSubmitRunner` and integration test **T6/T7** (real `AppDatabase.test`, real `ManualReturnService`, real `stockDao.getStock`).

Sequence proven in test:

1. First `submit` calls `service.processManualReturn` → **commits** return row and stock (+1 from `initialStock`).
2. `postSuccessRefresh` throws on first attempt → outcome `postSuccessRefreshFailed`.
3. `keyForFingerprint(intent.fingerprintHash)` remains **non-null** (UUID retained).
4. Second `submit` with same intent reuses bound key (`generateUuid` would return `'must-not-mint'`).
5. Second pass uses **real** `processManualReturn` again (not a stub replay response).
6. Assertions: `returnCount() == 1`, `stockLevel == initialStock + 1` after both attempts; map entry cleared only after second success.

This demonstrates **service-level replay** with **one** `customer_returns` row and **one** stock increment — not a mocked same-key callback.

**Gap (non-blocker):** T6/T7 does not pump `CustomerReturnsScreen` or reopen the dialog; it re-submits via the same runner instance. That is equivalent to screen state surviving dialog close/reopen because the runner is a field on screen state and is not recreated per dialog.

---

## 6. Intentional identical new return

**Conformance: yes.**

- **T10** (state): clearing `'fp-done'` leaves `'fp-open'` bound — selective slot clear.
- **T11** (integration): two full `runner.submit` successes with identical `ManualReturnSubmitIntent`; `mintSeq` goes 1 → 2; `returnCount() == 2`; `stockLevel == initialStock + 2`.

Legitimate consecutive returns with identical fields are **not** permanently blocked; only the fingerprint slot cleared after confirmed success allows a new UUID.

---

## 7. Conflict and failure retention

**Conformance: yes.**

| Scenario | Code | Test |
|----------|------|------|
| Conflict, no rotation | Runner conflict branch; map untouched | T8 (state + integration with thrown `ManualReturnIdempotencyConflictException`) |
| Pre-commit failure | `serviceFailure`; map retained; retry with real service | T5 |
| Refresh failure after commit | `postSuccessRefreshFailed`; map retained | T6/T7 |
| Material payload → new fp | T2, T13 | Different keys in map |
| Normalized equivalence | T3 | Same fp |

Service-level conflict contract unchanged (B10 tests 10–13, 28 still pass in last full B10 run).

**Screen handlers:** No path in `_submitManualReturn` clears the sticky map on exception or conflict.

---

## 8. Double-submit and concurrency

**Conformance: yes.**

- **Authoritative guard:** `_inFlight` on runner (`customer_manual_return_idempotency.dart:108–110`, `:118`, `:135–136`).
- **Dialog UX:** Save disabled when `_manualReturnSubmitRunner.inFlight` (`customer_returns_screen.dart:403–405`).
- **T9:** `Completer` gate — second `submit` returns `skippedInFlight` while first blocked; `calls == 1`; no `Future.delayed` in B30 suite (grep confirmed).
- **Global serialization:** One runner per screen → at most one manual-return service call in flight per screen instance (design B; replaces prior `_manualReturnSubmitting`, which is absent from manual path).
- **Independent intents:** T12 — two fingerprint hashes → two map entries.

B10 widget test **24** (UI double-submit) still passes — complements T9 at widget layer for the old guard pattern; B10 **27** fails for the **new** conflict-retention policy (see §9).

**Optional UX note:** `skippedInFlight` returns silently (no snackbar). Not a financial correctness issue.

---

## 9. B10 regression classification (reconfirmed)

Executed `flutter test test/customer_manual_return_idempotency_b10_test.dart` during implementation verification; reconfirmed assertions in source.

| Test | Class | Evidence |
|------|-------|----------|
| **21** | **A** — pre-existing schema pin | `expect(migrated.schemaVersion, 50)` at `b10_test.dart:579` fails with `Actual: <51>` before table check. |
| **22** | **A** | `expect(db.schemaVersion, 50)` at `:584`; app `schemaVersion => 51`. |
| **29** | **A** | `expect(regressionDb.schemaVersion, 50)` at `:591`. |
| **27** | **B** — expected B30 UI change | `:1142–1143` requires `keysUsed[0] != keysUsed[1]` after conflict then identical resubmit; B30 reuses UUID. B30 **T8** asserts retention at runner level. B10 service tests **not** weakened. |

No B30 production change to schema, migrations, or B10 test file.

---

## 10. Test quality (T1–T13)

| ID | Proves claimed invariant? | Notes |
|----|---------------------------|-------|
| T1–T3 | Yes | Unit fingerprint contract |
| T4 | Partial | Simulates “reopen” via second `prepareReturnKey`, not widget dialog — adequate for map semantics |
| T5 | Yes | Real service on retry; one return row |
| T6/T7 | Yes | **Critical:** real DB + stock + real service replay |
| T8 | Partial | Integration uses **thrown** conflict, not DB mismatch; service conflicts covered by B10 |
| T9 | Yes | Completer barrier; real service on first call |
| T10 | Partial | Calls `clearReturnKey` directly on state; design matrix asked for post-success integration — **mitigated by T11/T6/T7** clearing via successful `submit` |
| T11 | Yes | Two persisted returns + stock +2 |
| T12 | Yes | Map isolation |
| T13 | Yes | Different mint seq for different intents |

**T14 (B10 service unchanged):** Satisfied by unchanged `ManualReturnService` diff and 26 passing B10 tests including core idempotency 1–20.

**Gaps (should-fix, not blockers):**

1. T10 does not assert `keyForFingerprint` is null after a **successful** `runner.submit` (only manual `clearReturnKey`).
2. No widget test for B30-specific lifecycle (post-refresh failure / conflict retention through `CustomerReturnsScreen`); financial paths are covered at runner + real service layer.

---

## 11. Backend / schema boundary

| Check | Result |
|-------|--------|
| `schemaVersion` | 51 (`app_database.dart:221`) — unchanged vs baseline |
| `ManualReturnService` | No diff from baseline |
| `ManualReturnFingerprint` | No diff from baseline |
| DAO / table / migrations | No B30 diff |
| Quick / supplier returns | Untouched in B30 files |

B28 reference: refund settlement clears sticky key **before** invalidation (`customer_refund_settlement_provider.dart:292–298`). B30 correctly follows **approved B29-style ordering** (clear **after** post-success refresh), per design §7.1.

---

## 12. Analyzer, encoding, diff

| Check | Result |
|-------|--------|
| `dart analyze` (B30 production files) | No issues found |
| B30 tests | `flutter test …b30_test.dart` → **13/13 passed** (review re-run) |
| NULL bytes | 0 on `customer_manual_return_idempotency.dart`, `customer_returns_screen.dart`, `b30_test.dart` |
| `git diff --check` (production + B30 test) | Clean |

---

## 13. Findings by severity

### BLOCKER

None.

### SHOULD-FIX

1. **T10 matrix drift:** Test validates `clearReturnKey` in isolation, not `keyForFingerprint == null` after successful `runner.submit`. Add a short assertion on the runner path (or rename T10 to “state API”) to prevent future regressions conflating API with lifecycle.
2. **T8 integration depth:** Conflict retention is proven with a synthetic throw; consider one integration test that provokes real `ManualReturnIdempotencyConflictException` via same key + different payload (optional redundancy with B10 10–13).

### OPTIONAL

1. Widget-level B30 lifecycle test (dialog reopen + sticky runner) for parity with obsolete B10 test 27 replacement.
2. User feedback when `skippedInFlight` (double submit after dialog closed).
3. Process death loses in-memory map (accepted in design §5).
4. B10 tests 21/22/29 schema pin hygiene (50 vs 51).

---

## 14. Final verdict

**B30 REVIEW PASS WITH SHOULD-FIX**

Implementation matches the approved B30 design on fingerprint contract, sticky lifecycle, post-commit financial safety (real service/DB in T6/T7), intentional identical new returns (T11), conflict/failure retention, and scope boundaries. No duplicate-return or duplicate-stock path was identified under the approved single-screen, single-process model. Residual items are test-documentation gaps, not production correctness defects.

Review Pass complete — no fixes applied.

---

## 15. Review fixes resolution (2026-10-19)

This section records closure of the **SHOULD-FIX** items from §13. The original Review Pass verdict (**B30 REVIEW PASS WITH SHOULD-FIX**) and findings above remain historical evidence.

### SF-01 — T10 success lifecycle

**Original finding (§13):** T10 called `clearReturnKey` on state in isolation; did not prove successful `CustomerManualReturnSubmitRunner.submit` clears only the completed fingerprint slot.

**Resolution:** Replaced state-level T10 with integration test **`T10 success clears only completed fingerprint slot (runner)`** in `test/customer_manual_return_idempotency_b30_test.dart`. Uses real `ManualReturnService` + DB; two distinct pending fingerprints; asserts `success`, null `keyForFingerprint` for completed intent, unchanged binding for pending intent, map size 1.

**Status:** **Resolved**

### SF-02 — T8 real service conflict

**Original finding (§13):** T8 integration used a synthetic thrown conflict only.

**Resolution:** Added **`T8 real service conflict retains key without DB mutation`**: seal with key K and qty 1, then runner submit with qty 2 reusing K; real `ManualReturnIdempotencyConflictException`; sticky binding retained; one return row; stock unchanged. Renamed prior test to **`T8 conflict retains key (runner synthetic)`**; kept for fast runner-path coverage.

**Status:** **Resolved**

### Verification (review fixes)

| Check | Result |
|-------|--------|
| B30 suite | **14/14 passed** |
| T6/T7, T11 | Still pass (same file run) |
| B10 conflict service tests 10–13, 28 | Pass (targeted re-run) |
| Production diff vs baseline | `customer_returns_screen.dart` only (unchanged by this task) |
| Schema | 51 |
| `git diff --check` (B30 test) | Clean |
| NULL bytes (B30 test) | 0 |

### Post-fix verdict

**B30 REVIEW FIXES VERIFIED**

Optional items from §13 (widget-level B30 test, `skippedInFlight` UX, B10 schema pins 21/22/29, process death) remain open and were not in scope for this task.