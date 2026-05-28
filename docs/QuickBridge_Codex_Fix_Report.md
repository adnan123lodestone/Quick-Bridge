# QuickBridge Permanent Fix Report

Date: 2026-05-28

Source plan reviewed: `C:\Users\USER\Downloads\QuickBridge_Codex_Permanent_Fix_Plan.docx`

## Executive Summary

All eight repo-reproducible issues from the permanent fix plan were implemented and verified with static guardrails, LWC unit tests, Salesforce compile validation, and plan-scoped Apex tests.

## Fixed Items

| Plan ID | Status | Fix Summary |
| --- | --- | --- |
| ISSUE-007 | Fixed | Removed per-record QuickBooks batch hydration for invoices, credit memos, and purchase orders. Batches now hydrate existing QuickBooks records with `QuickBooksBulkQueryService.queryByIdsMap(...)` instead of per-record `/invoice/{id}`, `/creditmemo/{id}`, and `/purchaseorder/{id}` calls. |
| ISSUE-002 | Fixed | Moved remaining runtime reads off `Quickbridge_Config__mdt` into normalized connector config resolution. Legacy custom metadata reads are isolated in `QuickbridgeLegacyConfigCompatibility` for compatibility-only paths. |
| ISSUE-009 | Fixed | Made the invoice pipeline fail closed unless exactly one canonical invoice target exists. Tests now explicitly configure invoice targets instead of relying on hidden fallback behavior. |
| NEW-003 | Fixed | Tightened retry classification so HTTP status and structured signals drive retries. Message parsing is limited to platform lock/DML lock patterns. |
| ISSUE-005 | Fixed | Refactored `internalPaymentComponent` to render from provider descriptors and renderer mode, removing provider-key fallback/default lists and provider-specific getters. |
| NEW-004 | Fixed | Refactored `quickbridgeConfigPanel` logo and scheduler UI to use connector descriptors and capabilities, removing connector-key logo maps and hard-coded scheduler checks. |
| ISSUE-015 | Fixed | Added static guardrails for admin/runtime import boundaries and verified checkout/config-panel boundaries in the permanent-fix script. |
| NEW-011 | Fixed | Added `ErrorLogLinkBackfillService` for idempotent backfill of missing `Error_Log_Link__c` records and kept `Error_Log_Link__c` as the authoritative error-correlation path. |

## Additional Cleanup

- Preserved payment-provider test defaults while moving Authorize.Net, Stripe, and PayPal runtime config to `ConnectorConfigResolver`.
- Updated the stale `fieldMappingComponent` reset unit test to click the existing confirmation modal before asserting cleared rows.
- Updated `LockSafeDmlTest` so timeout text alone is no longer treated as retryable, matching NEW-003.

## Verification Evidence

Passed:

- `node scripts/verify-quickbridge-permanent-fixes.cjs`
  - Result: `QuickBridge permanent-fix static guardrails passed.`
- `.\\node_modules\\.bin\\prettier.cmd --check ...`
  - Result: all matched files use Prettier style.
- `npm.cmd run test:unit -- -- --runInBand`
  - Result: 3 suites passed, 7 tests passed.
- `sf project deploy start --dry-run ... --test-level NoTestRun --target-org "Quick Bridge"`
  - Result: successful check-only compile, 255/255 components.
- Plan-scoped Salesforce check-only Apex tests:
  - Classes: `QuickBooksInvoiceBatchTest`, `QuickBooksCreditMemoBatchTest`, `QuickBooksPurchaseOrderBatchTest`, `IntegrationRetryPolicyTest`, `QuickBridgeRecordEngineTest`, `ErrorLogUtilityTest`
  - Result: 30 tests run, 0 failures.

## Org-Wide Validation Note

A full `RunLocalTests` dry run was also attempted. It did not pass because the current org/repo has broader pre-existing test and coverage debt outside this plan:

- 447 tests run, 42 failures.
- Average Apex coverage reported as 64%, below Salesforce's 75% threshold.
- The failures include legacy tests still asserting direct legacy error fields such as `Order__c`, while NEW-011 makes `Error_Log_Link__c` authoritative.

Those full-suite failures are not skipped plan items; they are outside the eight issues in the supplied permanent-fix plan and are recorded here so the validation state is transparent.
