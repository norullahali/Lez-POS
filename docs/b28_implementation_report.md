# B28 Implementation Report — Customer Refund Settlement Operation-Intent Idempotency

**Date:** 2026-10-14  
**Baseline HEAD:** `9ff31d2d67e87e788abc25508de45a85cd68d569`  
**Schema:** 51 (unchanged)  
**Commit/push:** NOT performed

## Files changed

| File | Change |
|------|--------|
| `lib/features/customers/customer_refund_settlement_idempotency.dart` | **New** — sticky map fingerprintHash → UUID |
| `lib/core/services/customer_refund_settlement_intent_fingerprint.dart` | **New** — SHA-256 intent hash mirroring service fields |
| `lib/features/customers/providers/customer_refund_settlement_provider.dart` | `init()` no UUID; `submit()` prepareKey + clear on success; map survives `reset()` |
| `test/customer_refund_settlement_idempotency_b28_test.dart` | **New** — 15 tests |
| `docs/b28_implementation_report.md` | This report |

**Not modified:** `CustomerRefundSettlementService`, DAO, table, dialog (no changes required).

## Lifecycle

- **Owner:** `CustomerRefundSettlementUiNotifier.settlementIdempotency`
- **init:** UI fields only
- **reset:** UI state null only; sticky map retained
- **submit:** validate → fingerprint → `prepareSettlementKey` → `settleCredit` → success clears key; failures/conflicts retain key
- **Replay:** success path clears key (same as fresh success)

## Fingerprint contract

`customerId`, `amount` (6 dp canonical), `returnId` (nullable), `note` as `(note ?? '').trim()` — aligned with `_fingerprintMatches`.

## Backend / schema

No service, DAO, migration, or schema changes. Phase C replay/conflict semantics unchanged.

## Tests

| Suite | Result |
|-------|--------|
| B28 | **15/15** |
| Phase C idempotency (`customer_refund_idempotency_phase_c_step_3_0_test.dart`) | **14/16** — tests **M/N** expect schema v34; app is v51 (pre-existing migration assertions) |
| UI Step 2.3 (`customer_refund_settlement_ui_phase_c_step_2_3_test.dart`) | **All passed** |

B24/B27 not modified; not re-run.

## Analyzer

`dart analyze` on three B28 production files: **No issues found**

## Hygiene

- `git diff --check`: clean (tracked provider diff)
- New Dart files: UTF-8, no BOM (verified after write)

## Process-death limitation

In-memory sticky map only; kill after commit before UI clear can still allow new UUID on reopen — **out of B28 scope** (documented in design).

## Ready for Review Pass

Yes — implementation matches approved Option C design.