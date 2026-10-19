# B30 Implementation Report â Customer Manual Return UI Operation-Intent Idempotency

**Date:** 2026-10-19  
**Baseline HEAD:** `da030ab538015ee44661f17c2869ecb902dd3ac8`  
**Schema:** 51 (unchanged)  
**Design reference:** `docs/b30_design_review.md`

**Verification verdict (B10 regression triage):** **B30 IMPLEMENTATION VERIFIED** â no B30 defect found; four B10 failures are **(A)** schema pin drift or **(B)** intentional UI lifecycle change (test 27).

---

## 1. Files changed

| File | Action |
|------|--------|
| `lib/features/returns/customer_manual_return_idempotency.dart` | **Added** â fingerprint helper, sticky state, submit runner |
| `lib/features/returns/screens/customer_returns_screen.dart` | **Modified** â manual return path only |
| `test/customer_manual_return_idempotency_b30_test.dart` | **Added** â T1âT13 matrix |
| `docs/b30_implementation_report.md` | **Added** â this report |

No changes to `ManualReturnService`, `ManualReturnFingerprint`, DAO/table/schema, quick-return path, or supplier paths.

---

## 2. Implementation summary

### 2.1 Sticky intent map

`CustomerManualReturnIdempotencyState` mirrors B28/B29:

- `prepareReturnKey(fingerprintHash, generateUuid)` â stable UUID per fingerprint
- `clearReturnKey(fingerprintHash)` â only after confirmed success path

### 2.2 Canonical fingerprint

`computeManualReturnIntentFingerprint` delegates to `ManualReturnFingerprint.compute` with the same normalization the service applies (`roundAmount`, `normalizeReason`, `approvedByUserId: null` in production UI).

`ManualReturnSubmitIntent` exposes `fingerprintHash` for tests and submit orchestration.

### 2.3 Submit orchestration

`CustomerManualReturnSubmitRunner.submit`:

1. Guard `_inFlight` (double-submit)
2. Bind key via sticky map
3. `invokeService(returnKey)` â `ManualReturnService.processManualReturn`
4. `postSuccessRefresh()` â invalidations; **on throw** â `postSuccessRefreshFailed`, **key retained**
5. On refresh success â `clearReturnKey(fingerprint)` â `success`
6. Conflict / pre-commit failure â key **retained**

### 2.4 Screen wiring

`_CustomerReturnsScreenState` uses one `CustomerManualReturnSubmitRunner`:

- Removed per-attempt `_manualReturnIdempotencyKey` / `_clearManualReturnAttempt` on dialog open (L331 clear removed)
- Outcome-specific snackbars (success, refresh failure, conflict, generic failure)
- Dialog save button disabled while `inFlight`

---

## 3. Key lifecycle (implemented)

| Event | Behavior |
|-------|----------|
| First submit | `prepareReturnKey` mints or reuses UUID |
| Double submit | Second call â `skippedInFlight` |
| Service success + refresh OK | Clear fingerprint slot only |
| Service replay | Same key; one DB row |
| Pre-commit failure | Key retained |
| Conflict | Key retained (no auto rotation) |
| Post-commit refresh failure | Key retained; retry replays |
| Dialog reopen | Map not cleared |
| Fingerprint change | New map entry / new UUID |
| Success then identical new return | Slot cleared â new UUID (T11) |

---

## 4. Post-commit ambiguity (T6/T7)

Verified in integration test:

1. Service commits return + stock + seal
2. First `postSuccessRefresh` throws
3. Outcome `postSuccessRefreshFailed`; sticky key remains
4. Second submit with same intent reuses key
5. Service replays â **1** return row, **1** stock delta (+1)

---

## 5. Intentional identical new return (T11)

After first full success (slot cleared), second submit with identical fields mints **new** UUID and creates a **second** legitimate return (2 rows, stock +2).

---

## 6. Tests

### 6.1 B30 suite

```text
flutter test test/customer_manual_return_idempotency_b30_test.dart
00:01 +14: All tests passed!
```

(Re-verified after Review Pass SHOULD-FIX tests, 2026-10-19.)

| ID | Coverage |
|----|----------|
| T1âT3 | Fingerprint unit tests |
| T4 | Reopen preserves key |
| T5 | Pre-commit failure retains key |
| T6/T7 | Post-commit refresh failure + replay |
| T8 | Conflict retains key (state + runner synthetic + **real service**) |
| T9 | Double submit â Completer gate, one service call |
| T10 | **Runner** success clears only completed fingerprint slot (real service) |
| T11 | Two intentional identical returns |
| T12 | Independent fingerprints |
| T13 | Payload change â different keys |

T14: B10 suite run separately (below).

### 6.2 B10 suite (re-run for verification triage)

```text
flutter test test/customer_manual_return_idempotency_b10_test.dart
00:12 +26 -4: Some tests failed.
```

No edits were made to `customer_manual_return_idempotency_b10_test.dart` per scope rules.

#### 6.2.1 Failure classification (evidence from test output + source)

| Test | Class | Cause (evidence) | B30 involvement |
|------|-------|------------------|-----------------|
| **21)** migration v41 â v42 creates table | **A** â pre-existing schema pin | After migration, test asserts `expect(migrated.schemaVersion, 50)` at `customer_manual_return_idempotency_b10_test.dart:579`; runner reports `Expected: <50> Actual: <51>`. Table existence assertion is not reached. | **None** â `git diff da030abâ¦ -- lib` touches only `customer_returns_screen.dart`; no change to `app_database.dart` or B10 file. |
| **22)** fresh v42 schema includes table | **A** | `expect(db.schemaVersion, 50)` at `:584`; same `Actual: <51>`. Production: `int get schemaVersion => 51` in `app_database.dart:221`. | **None** |
| **29)** B2âB9 regression sentinel on v42 | **A** | `expect(regressionDb.schemaVersion, 50)` at `:591`; same failure. Subsequent sentinel queries (B10/B9 tables, B4 index) never run. | **None** |
| **27)** UI conflict clears key for next attempt | **B** â expected B30 UI lifecycle change | Spy service throws `ManualReturnIdempotencyConflictException` on first submit (`throwConflict = true`, `:1114â1117`). After reopen + identical resubmit, test expects `keysUsed[0] isNot keysUsed[1]` at `:1143`. Actual: same UUID both times (`Expected: not '4d325f58-â¦' Actual: '4d325f58-â¦'`). B30 runner does not call `clearReturnKey` on conflict (`customer_manual_return_idempotency.dart:130â131`); `prepareReturnKey` reuses the bound UUID. | **Intentional** per design review lifecycle **F** (retain key on conflict). Service conflict tests **10â13** and **28** still **pass**. |

**Not failures:** Tests **1â20**, **23â26**, **28**, **30** pass (26 total).

**Test 23 note:** Title suggests dialog open clears a pending key, but the flow only **cancels** without submitting, so no sticky key is ever bound. The test asserts one service call and one key after cancel â reopen â submit; it does not require key rotation and remains compatible with B30.

#### 6.2.2 Test 27 â obsolete assertion vs service regression

Test 27 encodes **pre-B30 UI policy**: after conflict, discard the idempotency UUID so the next attempt with unchanged fields gets a **new** key (see `docs/b30_design_review.md` Â§1.3 â conflict used to clear the attempt).

Approved B30 requires **retain** `fingerprintHash â UUID` on conflict (no automatic rotation) until the user changes material payload or completes a full success path. B30 **T8** and **T4** assert the new contract at runner/state level; test 27 is **not** a service-level idempotency regression.

**If full B10 green is required later:** narrowly update or supersede test 27 in a test-only pass â not required for B30 verification; **not applied** here.

---

## 7. Analyzer

```text
dart analyze lib/features/returns/customer_manual_return_idempotency.dart lib/features/returns/screens/customer_returns_screen.dart
No issues found!
```

---

## 8. Schema verification

`lib/core/database/app_database.dart`: `int get schemaVersion => 51;` â unchanged.

---

## 9. Encoding and diff checks

| File | NULL bytes |
|------|------------|
| `customer_manual_return_idempotency.dart` | 0 |
| `customer_returns_screen.dart` | 0 |
| `customer_manual_return_idempotency_b30_test.dart` | 0 |

`git diff --check` on production/test paths: **clean** (no whitespace errors reported).

---

## 10. B30 invariant reconfirmation (code + tests)

| Invariant | Implementation | Test |
|-----------|----------------|------|
| Post-commit refresh failure retains UUID | `postSuccessRefreshFailed` without `clearReturnKey` (`customer_manual_return_idempotency.dart:122â126`) | T6/T7 |
| Retry replays; one return + one stock mutation | Second `submit` reuses bound key | T6/T7 |
| Conflict retains key; no rotation | Conflict branch returns outcome only; map untouched (`:130â131`) | T8 |
| Success then identical fields â new UUID | `clearReturnKey` after refresh OK (`:128â129`) | T11 |
| One success clears only its fingerprint slot | Partial clear on map | T10 (runner integration) |
| Dialog reopen does not clear sticky map | Persistent `_manualReturnSubmitRunner` on screen state; no map clear in `_showCustomerReturnDialog` | T4 |
| Double submit one service call | `_inFlight` guard | T9; B10 test **24** passes |

---

## 11. Unresolved / follow-up

1. **B10 UI test 27** â obsolete UI policy; B30 T8 is the replacement contract.
2. **B10 tests 21/22/29** â update pinned `schemaVersion` from 50 to 51 (or assert `>= 42` plus table sentinels) in a migration-hygiene pass; not caused by B30.
3. **Process death** â in-memory sticky map not durable (accepted, same as B27âB29).

---

## 12. Git status (implementation artifacts)

- Modified: `lib/features/returns/screens/customer_returns_screen.dart`
- Untracked: `lib/features/returns/customer_manual_return_idempotency.dart`, `test/customer_manual_return_idempotency_b30_test.dart`, `docs/b30_implementation_report.md`

No commit, no push, no staging.
---

## 13. Review fixes (SF-01 / SF-02)

**Date:** 2026-10-19  
**Production code:** unchanged (test + docs only).

| ID | Test name | Resolution |
|----|-----------|------------|
| **SF-01** | `T10 success clears only completed fingerprint slot (runner)` | Two pending fingerprints (qty 1 and 2); successful `runner.submit` on one intent via real `ManualReturnService`; completed slot null; pending slot retains UUID; map size 1. Removed state-level T10 that called `clearReturnKey` directly. |
| **SF-02** | `T8 real service conflict retains key without DB mutation` | Seal return with key K + qty 1; `runner.submit` for qty 2 binds same K; real `ManualReturnIdempotencyConflictException`; binding retained; return count and stock unchanged. Synthetic test renamed `T8 conflict retains key (runner synthetic)`. |

```text
flutter test test/customer_manual_return_idempotency_b30_test.dart
00:01 +14: All tests passed!
```

B10 service conflict subset (unchanged semantics): tests **10-13**, **28** — all passed (targeted `--plain-name` re-run).

**Review fixes verdict:** **B30 REVIEW FIXES VERIFIED**