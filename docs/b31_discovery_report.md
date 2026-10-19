# B31 Discovery Report — Lez POS Next Milestone

**Discovery date:** 2026-10-19
**Mode:** READ-ONLY discovery (no production/test/schema/git mutations)
**Project:** Lez POS
**Prior milestone:** B30 CLOSED (`feat(returns): make manual return submissions idempotent`, `336dd3f`)

---

## 1. Verified baseline

| Check | Expected | Actual |
|-------|----------|--------|
| Branch | `main` | `main` |
| `git rev-parse HEAD` | `336dd3f1df1742615c9da278f6d012bce8cc9398` | **336dd3f1df1742615c9da278f6d012bce8cc9398** |
| `git rev-parse origin/main` | same as HEAD | **336dd3f** (synchronized) |
| Parent of HEAD | `da030ab…` (B29) | **da030ab538015ee44661f17c2869ecb902dd3ac8** |
| HEAD message | B30 feat | `feat(returns): make manual return submissions idempotent` |
| Schema | 51 | **51** (`lib/core/database/app_database.dart:221`) |
| Staged / modified tracked | none expected | **None** — only unrelated `??` untracked paths |
| Unexpected tracked drift | none | **None** |

**Untracked files (preserved, not B31 scope):** other milestone docs (`docs/b22_*`, `docs/b28_*`, Phase C docs, `post_b*` discoveries), `tool/*` scripts — not treated as approved product changes.

Discovery read **committed** source at `336dd3f` plus working-tree status; no stage/commit/push/clean/reset.

---

## 2. Architecture context (post-B30)

### 2.1 Idempotency pattern in-repo

Recent milestones (B27–B30) established **UI operation-intent idempotency**:

- Canonical **fingerprint** in service layer (`*Fingerprint.compute`).
- Persistent seal keyed by **UUID** in Drift idempotency tables (B5–B10, B15, etc.).
- UI **sticky map** `fingerprintHash → UUID` on screen/notifier (B27, B28, B29, **B30**).
- Clear fingerprint slot only after **service success + post-success refresh** (B29/B30 ordering).

### 2.2 Customer returns screen (verified after B30)

| Path | UI orchestration | Service | Post-B30 status |
|------|------------------|---------|-----------------|
| Manual return | `CustomerManualReturnSubmitRunner` + `customer_manual_return_idempotency.dart` | `ManualReturnService.processManualReturn` | **B30 closed** |
| Quick return (no invoice) | Screen scalar `_quickReturnIdempotencyKey` + `_clearQuickReturnAttempt()` | `PosSaleService.processQuickReturn` | **Gap remains (P1)** |
| Invoice-linked / smart lookup | Other dialogs/services | `CustomerInvoiceReturnService`, etc. | Service idempotency closed; UI intent P2 |

### 2.3 Test / regression landscape

- **B30:** `test/customer_manual_return_idempotency_b30_test.dart` — 14 tests (committed).
- **B10 full suite:** 26 pass / 4 fail documented at B30 audit (schema pins 21/22/29; obsolete UI test 27).
- **B9** mirrors B10 structure including UI lifecycle tests expecting **key clear on conflict** (`customer_quick_return_idempotency_b9_test.dart` group `B9 customer quick return UI lifecycle`, tests 26–28).

---

## 3. Candidate milestones (evidence-based)

### Candidate A — Customer quick return UI operation-intent idempotency (recommended)

| Field | Detail |
|-------|--------|
| **Title** | Customer quick return UI operation-intent idempotency |
| **Problem** | Same business intent can be submitted with **different UUIDs**, creating duplicate quick returns, stock moves, and session-linked refund effects. |
| **User/business impact** | Inventory inflation; duplicate no-invoice returns; distorted session/cash reporting. |
| **Evidence** | `customer_returns_screen.dart`: `_submitQuickReturn` (L174–237) uses `_quickReturnIdempotencyKey ??= v4()`, **`_clearQuickReturnAttempt()` on success (L200)** and **on conflict (L213)**; `_showQuickReturnDialog` calls **`_clearQuickReturnAttempt()` at open (L439)**. Service: `PosSaleService.processQuickReturn` (L315+) seals per key; replay only when same key + fingerprint (`pos_sale_service.dart` L341–350). **B9 test 15** (`customer_quick_return_idempotency_b9_test.dart`): different keys → two legitimate returns. B30 discovery explicitly deferred quick return as separate milestone (`docs/b30_discovery_report.md` §7 out-of-scope). |
| **Files / workflows** | `lib/features/returns/screens/customer_returns_screen.dart` (quick path only); new helper mirroring `customer_manual_return_idempotency.dart` using `QuickReturnFingerprint`; tests `test/customer_quick_return_idempotency_b31_test.dart` (proposed). Service: `lib/core/services/pos_sale_service.dart`, `lib/core/services/quick_return_fingerprint.dart`, `customer_quick_return_idempotency` DAO/table (unchanged). |
| **Schema** | **Not required** (Option A — UI sticky map only; same as B30). |
| **Risk / scope** | **Medium-low** if limited to quick-return submit path; pattern proven in B30. |
| **Dependencies** | Open POS session rules for quick return (existing service validation); manager approval path unchanged. |
| **Verification** | Mirror B30 matrix: fingerprint unit tests, sticky map, post-commit refresh failure + replay, real-service conflict, T11-style intentional second return, double-submit Completer gate; B9 service tests unchanged. |
| **Priority now** | **High** — symmetric gap closed for manual return in B30; same screen, same failure modes. |

**Hypothesis (not defect):** Process-death loses in-memory map (accepted P2 for B27–B30).

---

### Candidate B — B9/B10 test suite hygiene (schema pins + obsolete UI lifecycle)

| Field | Detail |
|-------|--------|
| **Title** | Manual/quick return idempotency test suite alignment (schema 51 + B30/B31 UI policy) |
| **Problem** | Full B9/B10 runs report **4 failures** unrelated to service correctness. |
| **Evidence** | B10 tests 21/22/29 assert `schemaVersion == 50`; app is **51**. B10 test 27 and B9 test 27 expect **UUID rotation after conflict** — contradicts B30 (and proposed B31) retention policy. |
| **Schema** | None (test-only). |
| **Scope** | Test/docs-only milestone; no production behavior change. |
| **Priority** | **P3** — hygiene and CI signal; do after or alongside B31 to avoid false red builds. |

---

### Candidate C — Supplier purchase return UI operation-intent idempotency

| Field | Detail |
|-------|--------|
| **Title** | Supplier purchase-linked return UI sticky intent |
| **Problem** | `SupplierReturnDraftNotifier` clears `_submitIdempotencyKey` on success via `_clearSubmitAttempt()` (`supplier_return_draft_provider.dart` L152–155, L298); `reset()` clears attempt (L331–332). Different keys with same fingerprint can post twice (B15 service semantics). |
| **Impact** | Duplicate supplier return postings within returnable caps — **partially mitigated** by SQL caps (B30 discovery P2). |
| **Schema** | None for UI-only Option A. |
| **Priority** | **P2** — lower urgency than customer quick return; more workflow complexity. |

---

### Candidate D — POS sale after session closed (service guard)

| Field | Detail |
|-------|--------|
| **Title** | Reject or harden POS checkout when session closed mid-flow |
| **Problem** | Checkout reads open session once; race if session closes before commit (B30 discovery rank 3, P2). |
| **Evidence** | Requires deeper `pos_screen.dart` / `PosSaleService.processSale` session binding review — **not fully re-audited in this discovery pass**. |
| **Schema** | Possibly none; may be service-only guard. |
| **Priority** | **P2** — needs focused reproduction design. |

---

### Candidate E — Customer invoice return UI sticky intent

| Field | Detail |
|-------|--------|
| **Title** | Invoice-linked customer return cross-dialog intent |
| **Problem** | Dialog-scoped keys; reopen may mint new UUID (B30 inventory P2). |
| **Mitigation** | Returnable/refundable caps at service layer. |
| **Priority** | **P2** — narrower user path than quick return. |

---

## 4. Candidate comparison

| Rank | Candidate | Value | Risk reduction | Evidence | Scope clarity | Regression risk |
|------|-----------|-------|----------------|----------|---------------|-----------------|
| **1** | **A — Quick return UI intent** | High | High (stock + session) | **Strong** (parallel to pre-B30 manual gap) | High (B30 template) | Low |
| 2 | C — Supplier return UI | Medium | Medium | Medium | Medium | Medium |
| 3 | D — Closed session checkout | Medium | Medium | **Weak** (needs investigation) | Low | Medium |
| 4 | E — Invoice return UI | Medium | Medium | Medium | Medium | Medium |
| 5 | B — Test hygiene | Low (signal) | Low | **Strong** | High | None (tests only) |

---

## 5. Recommended B31 candidate

**Primary recommendation: Candidate A — Customer quick return UI operation-intent idempotency**

**Rationale:**

1. **Business value:** Quick (no-invoice) returns move stock and tie into POS session economics — duplicate submits are a direct integrity issue.
2. **Evidence strength:** Current source still exhibits the **exact anti-pattern B30 removed** for manual returns (clear key on success/conflict/dialog open).
3. **Scope clarity:** Reuse B30 architecture (`CustomerManualReturnSubmitRunner` analogue + `QuickReturnFingerprint`); touch **quick path only** on `CustomerReturnsScreen`.
4. **Testability:** B9 service suite + new B31 matrix; expect B9 UI test 27 to become obsolete (same as B10/27 after B30).
5. **Compatibility:** No schema/service change required for Option A; aligns with B27–B30 architecture.

**Explicit exclusions for B31 (recommended):**

- B30 manual return path (closed).
- `ManualReturnService` / `PosSaleService` semantic changes (unless design review proves Option A insufficient).
- Supplier returns, invoice-linked returns, POS session guard, purchase/payment flows.
- Unrelated untracked docs/tools in workspace.
- B9/B10 test pin updates (optional follow-on **Candidate B**, not bundled unless explicitly scoped).

---

## 6. Risks, dependencies, open questions

| Item | Type |
|------|------|
| Quick return requires **open session** and may require **manager approval** — fingerprint must include same parameters as `processQuickReturn` (incl. `approvedByUserId` when used). | Dependency |
| **Refund amount** is part of quick-return fingerprint — UI must pass stable normalized values. | Design detail |
| B9 UI tests 26–28 may fail after B31 (expected contract change, not service regression). | Test planning |
| In-memory sticky map lost on process death | Accepted P2 (same as B30) |
| Whether to add **widget-level** screen tests | Optional (B30 used runner + integration) |

**Unresolved (non-blocking):** Candidate D needs a short focused spike before design if prioritized over quick return.

---

## 7. Verification strategy (recommended B31)

1. Unit: `QuickReturnFingerprint` parity with service normalization (mirror B30 T1–T3).
2. Integration: real `AppDatabase.test` + `PosSaleService.processQuickReturn` for replay, post-commit refresh failure, real conflict (same key, different payload).
3. Lifecycle: conflict retains key; success clears slot; intentional identical second return gets new UUID.
4. Concurrency: Completer-gated double submit (no `Future.delayed` proof).
5. Regression: run B9 **service** idempotency tests; classify B9 UI 27 separately.
6. Analyzer + schema 51 unchanged + scope diff check.

---

## 8. Final discovery verdict

**B31 DISCOVERY READY FOR DESIGN REVIEW**

Recommended next step: **Design Review** for Customer quick return UI operation-intent idempotency (Option A sticky map, no schema), using `docs/b30_design_review.md` and `docs/b30_implementation_report.md` as structural templates.

Do **not** begin Design Review or implementation in this task.

---

*Discovery performed read-only at HEAD `336dd3f`; unrelated untracked files preserved.*