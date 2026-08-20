# Customer Returns Phase C Step 2.4 — Hardening Pass

Hardening mode: targeted Test A integrity fix (RH-1 only)
Baseline: Step 2.3 commit 24a45e2 + uncommitted Step 2.4 implementation
Hardening date: 2026-08-20

## 1. Previous Review Finding RH-1

Test A was weakened during implementation: it only checked repository eligibility and an overridden credit provider. It did not mount CustomerReturnDetailDialog or verify that an eligible customer return exposes the refund-capable CustomerCreditRefundEntry in the detail UI. The test overlapped Test B and overclaimed its name.

## 2. Root Cause

Two independent issues prevented the original widget approach:

1. Drift DB deadlock in testWidgets: Calling seedLinkedReturn() directly inside testWidgets (before pumpWidget) blocked indefinitely because Drift/async DB work must run under tester.runAsync() in widget tests.

2. pumpAndSettle / unbounded async hang: CustomerReturnDetailDialog watches customerReturnDetailProvider (a FutureProvider.autoDispose). In widget tests, Riverpod FutureProvider futures do not reliably complete across bounded tester.pump() calls when left to the default async path. The dialog remained on the loading branch (CircularProgressIndicator), so pumpAndSettle never settled. The implementation workaround replaced Test A with a unit-level eligibility assertion.

## 3. Exact Test A Weakness

Before hardening, Test A:

- Called readRepo.getCustomerReturnDetail() and asserted isRefundLinkEligible
- Read customerAvailableCreditProvider from a ProviderContainer with a hard-coded override (async => 25)
- Did not mount CustomerReturnDetailDialog
- Did not find or inspect CustomerCreditRefundEntry
- Did not assert enabled refund button in detail context
- Overlapped Test B (invoice/customer resolution + eligibility)

## 4. Hardening Change

Test A was converted back to testWidgets with deterministic async handling:

- DB seeding and read-model loading run inside tester.runAsync()
- CustomerReturnDetailDialog is mounted in a bounded SizedBox(900x700) with RTL MaterialApp
- Bounded pumpUntilFound helper (30 x 50 ms max) replaces pumpAndSettle
- Provider overrides supply pre-resolved read-model/credit data loaded from the real test database
- Widget assertions verify detail header, return metadata, embedded refund entry, and enabled refund button
- REFUND transaction count verified unchanged (no financial settlement)

## 5. Why the New Test Is Stronger

The hardened Test A fails if:

- CustomerReturnDetailDialog stops rendering eligible detail content
- CustomerCreditRefundEntry is removed from the eligible branch
- returnId or returnLabel are not propagated to the entry widget
- Positive customer credit is not reflected as an enabled refund button
- Opening the detail UI writes a REFUND transaction

It exercises the actual Step 2.4 integration path:

seeded eligible return -> CustomerReturnDetailDialog -> CustomerCreditRefundEntry -> enabled refund button

without performing settlement.

## 6. Provider Override Justification

| Override | Purpose | Does not bypass |
|---|---|---|
| customerReturnReadRepositoryProvider -> test readRepo | Routes reads to in-memory test DB | Dialog conditional logic |
| customerAccountsDaoProvider -> test DAO | Same | Entry enable/disable logic |
| customerReturnDetailProvider(returnId) -> pre-loaded detail from readRepo | Deterministic async resolution; detail is real seeded data | Dialog isRefundLinkEligible branch and entry embedding |
| customerAvailableCreditProvider(customerId) -> availableCredit computed from calculateBalanceFromTransactions | Deterministic async resolution; amount is real ledger credit | Entry hasCredit UI branch and button onPressed |

Overrides do not mock the dialog or entry. Eligibility and credit amounts are computed from the seeded database before overrides are applied. The dialog still renders CustomerCreditRefundEntry only when detail.isRefundLinkEligible is true (verified on the loaded model).

## 7. Assertions Added

- Detail header text containing تفاصيل مرتجع
- Return metadata label قيمة المرتجع (return total, not refundable balance)
- Return number visible in dialog (detail.displayReturnNumber)
- find.byType(CustomerCreditRefundEntry) present
- CustomerCreditRefundEntry.customerId, .returnId, .returnLabel match seeded values
- Credit banner الرصيد الدائن visible
- ElevatedButton استرداد من العميل has non-null onPressed
- REFUND row count unchanged before/after UI mount

## 8. Tests B-N Preservation

All tests B-N remain unchanged in name, scope, and assertions. Full Step 2.4 matrix verified after hardening.

## 9. Focused Test Result

flutter test test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart

14/14 PASS

## 10. Regression Result

flutter test (Step 2.4 + Step 2.3 + Step 2.1 + Step 2.2 + Phase C Step 1 + supplier refund suites) -j 1

Batch 1 (customer Phase C): 85/85 PASS
Batch 2 (supplier refund): 54/54 PASS
Total: 139/139 PASS

Note: single-process run of all nine files OOM'd on this machine; batched runs with -j 1 succeeded.

## 11. Analyzer Result

Scoped analysis on Step 2.4 test file and production scope files:

0 errors, 0 warnings

## 12. Format Result

dart format --set-exit-if-changed test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart

First pass: exit 1 (file needed formatting; formatter applied).
Second pass: exit 0 (0 files changed).

## 13. Build Result

flutter build windows --debug

PASS — build\windows\x64\runner\Debug\lez_pos.exe

## 14. Encoding Result

Test file verified: UTF-8 (no BOM, no null bytes). Arabic assertion strings compile and execute correctly in passing tests.

## 15. Production Code Scope

Hardening pass modified only:

- test/customer_return_linked_refund_ui_phase_c_step_2_4_test.dart
- docs/customer_returns_phase_c_step_2_4_hardening.md (this document)

git diff --name-only during hardening shows no new changes to protected Step 2.4 production files. Pre-existing uncommitted Step 2.4 implementation files remain as before hardening; hardening did not edit them.

Protected financial architecture unchanged.

## 16. Remaining Findings

From Review Pass (unchanged by this hardening scope):

- NB-1: Large format-only diff in customer_returns_screen.dart (cosmetic; pre-existing)
- NB-2: No widget test for ineligible detail-dialog warning branch (out of RH-1 scope)

RH-1 resolved.

## 17. Final Decision

FINAL DECISION: READY FOR FINAL AUDIT

Test A now genuinely proves eligible customer return -> CustomerReturnDetailDialog -> refund-capable CustomerCreditRefundEntry with correct returnId/returnLabel propagation and enabled refund entry when credit is available, without performing financial settlement.