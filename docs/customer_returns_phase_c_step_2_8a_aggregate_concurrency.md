# Customer Returns Phase C - Step 2.8A

## Aggregate Credit Concurrency Hardening

**Status:** Implementation complete (schema 32)

---

## Original concurrency gap

`CustomerRefundSettlementService.settleCredit()` performed an aggregate credit pre-check and then inserted REFUND via `recordRefundInTransaction()`. Two concurrent transactions could both pass the pre-check and commit, exceeding aggregate customer credit.

## Financial invariant

Aggregate credit = authoritative `SUM(customer_transactions.amount)`; available credit = `-balance` when balance < 0. After REFUND, aggregate credit must not be exceeded due to concurrent settlements.

## Chosen guard mechanism

No schema change (schema 32). Added `CustomerAccountsDao.recordRefundInTransactionIfWithinAggregateCredit()` using conditional INSERT ... SELECT ... WHERE `COALESCE(SUM(amount),0) + refund <= tolerance`. Success verified via `SELECT changes()`. Service uses guarded insert unless test override is set. Failure reuses `amountExceedsCredit`.

## Transaction order

Unchanged single Drift transaction: validate customer/amount/return, per-return cap checks, aggregate pre-check, **guarded REFUND insert**, conditional settled_amount increment, audit log.

## Linked and unlinked behavior

Guard applies to linked (`returnId != null`) and unlinked refunds. General Customer ID 1 unchanged.

## Rollback behavior

Failed guard = no REFUND. Failed per-return increment after REFUND = full rollback. Post-refund hook failure = full rollback.

## Concurrency test strategy

15 tests in `test/customer_refund_aggregate_concurrency_phase_c_step_2_8a_test.dart` using real Drift DB. Test E uses two connections on one SQLite file with busy_timeout.

## Known limitations

- Pre-check is not authoritative; conditional INSERT is.
- SQLITE_BUSY under lock contention may surface as unexpectedFailure while still preventing double commit.
- Guard does not replace Step 2.7B per-return caps.

## Schema impact

Schema version 32 unchanged.

## Files changed

- `lib/core/database/daos/customer_accounts_dao.dart`
- `lib/core/services/customer_refund_settlement_service.dart`
- `test/customer_refund_aggregate_concurrency_phase_c_step_2_8a_test.dart`
- `docs/customer_returns_phase_c_step_2_8a_aggregate_concurrency.md`
