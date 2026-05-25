# QuickBridge Four-Issue Status Report - 2026-05-25

## Executive Summary

This report covers the four requested open tracker items: `ISSUE-007`, `ISSUE-009`, `NEW-008`, and `NEW-021`.

Implementation work has been applied in the current dirty workspace. The focused compile-only Salesforce dry run succeeds, and the broader targeted dry run compiles all selected components with 34 of 34 targeted Apex tests passing. The targeted dry run is still marked failed by Salesforce because several selected Apex classes remain below the 75% per-class coverage threshold. Those coverage gaps are listed in New Findings.

The canonical PDF generator also passes the requested tracker count check and regenerated `QuickBridge_Issues_Tracker_3.pdf` with `PARTIAL=7 OPEN=4 TOTAL=11`.

## ISSUE-007 - QuickBooks Sync Still Uses N+1 Callout Pattern

Tracker status: `OPEN`

Implemented status: Code implemented, functionally validated by compile-only dry run and targeted tests. Final deploy is blocked only by coverage threshold warnings.

What changed:

- Added `QuickBooksBulkQueryService` as the shared QuickBooks `/query` bulk fetch helper for `Customer`, `Vendor`, `Item`, and `Invoice`.
- Added entity allowlisting so unsupported entity names fail before callout.
- Added ID chunking for query-by-ID fetches to avoid oversized QBO query strings.
- Added pagination for updated-since fetches with `STARTPOSITION` and `MAXRESULTS`.
- Updated scheduled and batch hydration paths:
  - `QBCustomerToAccountSyncBatch` now hydrates batch records through `QuickBooksBulkQueryService.queryUpdatedSince('Customer', ...)`.
  - `QBVendorToAccountSyncBatch` now hydrates batch records through `QuickBooksBulkQueryService.queryUpdatedSince('Vendor', ...)`.
  - `QBItemToProductSyncBatch` now hydrates batch records through `QuickBooksBulkQueryService.queryUpdatedSince('Item', ...)`.
  - `QBOInvoiceSyncQueueable` now hydrates invoice IDs through `QuickBooksBulkQueryService.queryByIds('Invoice', ...)`.
- Removed fallback single-record GET hydration from batch payload resolution. Single-record GET methods remain only in explicit single-record action methods.
- Added/updated tests to assert batch paths use the `/query` endpoint and do not call `/customer/`, `/vendor/`, `/item/`, or `/invoice/` loops.

Files touched:

- `force-app/main/default/classes/QuickBooksBulkQueryService.cls`
- `force-app/main/default/classes/QuickBooksBulkQueryServiceTest.cls`
- `force-app/main/default/classes/QBCustomerToAccountSyncBatch.cls`
- `force-app/main/default/classes/QBCustomerToAccountSyncBatchTest.cls`
- `force-app/main/default/classes/QBVendorToAccountSyncBatch.cls`
- `force-app/main/default/classes/QBVendorToAccountSyncBatchTest.cls`
- `force-app/main/default/classes/QBItemToProductSyncBatch.cls`
- `force-app/main/default/classes/QBItemToProductSyncBatchTest.cls`
- `force-app/main/default/classes/QBOInvoiceSyncQueueable.cls`
- `force-app/main/default/classes/QBOInvoiceSyncQueueableTest.cls`
- `force-app/main/default/classes/IntegrationRetryPolicy.cls`
- `manifest/package-quickbridge-issues-3.xml`

Validation evidence:

- Compile-only dry run succeeded: deploy ID `0Afal00002VcxAfCAJ`, 12 of 12 components validated.
- Targeted dry run compiled all selected components and ran 34 of 34 tests successfully.
- `QuickBooksBulkQueryServiceTest` covers chunking, pagination, and unsupported entity rejection.
- Batch mock assertions now fail if batch paths call single-record endpoints.

Remaining risk:

- The final targeted dry run fails the deploy gate because selected classes still have coverage below 75%.
- Bulk query page size and ID chunk size are conservative defaults; production QBO query length behavior should be watched after first deployment.

## ISSUE-009 - Invoice Processing Engine Is Not A Generic Pipeline

Tracker status: `OPEN`

Implemented status: Code implemented, functionally validated by targeted tests. Final deploy is blocked only by coverage threshold warnings on selected classes.

What changed:

- Kept `QuickBridgeRecordEngine.processIncomingInvoice(Map<String,Object>)` as the public entrypoint.
- Moved invoice target handling into a metadata-driven pipeline helper inside `QuickBridgeRecordEngine`.
- Treats `Invoice__c` as the default target while supporting additional active target mappings through `Invoice_Field_Mapping__mdt`.
- Replaced broad object describe resolution in the invoice engine with targeted `Schema.describeSObjects` caching.
- Added/strengthened tests for multiple target mappings, invalid target handling, field coercion, and canonical error-link behavior.

Files touched:

- `force-app/main/default/classes/QuickBridgeRecordEngine.cls`
- `force-app/main/default/classes/QuickBridgeRecordEngineTest.cls`
- `force-app/main/default/classes/ErrorLogUtility.cls`
- `force-app/main/default/classes/ErrorLogUtilityTest.cls`
- `force-app/main/default/classes/LockSafeDmlTest.cls`

Validation evidence:

- `QuickBridgeRecordEngine` appears in the successful focused targeted test run.
- The targeted deploy dry run ran 34 of 34 tests successfully.
- Static scan confirmed `QuickBridgeRecordEngine` uses `Schema.describeSObjects(...)` and does not use `Schema.getGlobalDescribe()`.

Remaining risk:

- The generic mapping pipeline depends on the active custom metadata rows present in the org. Additional regression coverage should be added as new target mappings are introduced.
- Deploy remains blocked by per-class coverage warnings in related selected classes, especially `ErrorLogUtility`.

## NEW-008 - QBOInvoiceSyncQueueable And QBOWebhookService Use without sharing

Tracker status: `OPEN`

Implemented status: Code implemented, functionally validated by compile-only dry run and targeted tests. Final deploy is blocked only by coverage threshold warnings.

What changed:

- `QBOInvoiceSyncQueueable` is declared `with sharing`.
- `QBOWebhookService` is declared `with sharing`.
- `QBOInvoiceSyncQueueable` now uses explicit `AccessLevel.USER_MODE` DML for supported inserts, upserts, and deletes instead of silently relying on system-mode writes.
- Webhook verification remains fail-closed:
  - `503` when the verifier token is unavailable.
  - `401` for invalid or missing signatures.
  - `200` only after valid signature handling.
- Added/updated tests around webhook verification and queueable behavior.

Files touched:

- `force-app/main/default/classes/QBOInvoiceSyncQueueable.cls`
- `force-app/main/default/classes/QBOInvoiceSyncQueueableTest.cls`
- `force-app/main/default/classes/QBOWebhookService.cls`
- `force-app/main/default/classes/QBOWebhookServiceTest.cls`
- `force-app/main/default/classes/ErrorLogUtility.cls`
- `force-app/main/default/classes/IntegrationRetryPolicy.cls`

Validation evidence:

- Focused compile-only dry run succeeded after including local dependency changes.
- Targeted dry run ran 34 of 34 tests successfully.
- Static scan confirmed both QBO classes are now `with sharing`.
- Static scan confirmed `QBOInvoiceSyncQueueable` uses `AccessLevel.USER_MODE` DML.

Remaining risk:

- Salesforce still reports low per-class coverage for `QBOInvoiceSyncQueueable` and `QBOWebhookService`.
- User-mode DML may expose real production permission gaps after deployment. That is expected and preferred over silent system-context writes, but admins should be ready to update permission sets for legitimate sync users.

## NEW-021 - Issues Tracker PDF Generator Still Needs A Single Canonical Implementation

Tracker status: `OPEN`

Implemented status: Code implemented and executable count check passed.

What changed:

- Added `scripts/generate_issues_tracker_pdf.py` as the canonical tracker PDF generator.
- The script reads the tracker source once, derives status counts from parsed issue rows, and renders the PDF from that parsed model.
- Added an executable count check with `--print-counts`.
- Regenerated `QuickBridge_Issues_Tracker_3.pdf` from the source tracker document after the count check passed.

Files touched:

- `scripts/generate_issues_tracker_pdf.py`
- `QuickBridge_Issues_Tracker_3.pdf`

Validation evidence:

- Count command output: `PARTIAL=7 OPEN=4 TOTAL=11`.
- PDF generation command completed successfully and wrote `QuickBridge_Issues_Tracker_3.pdf`.

Remaining risk:

- The current generator is validated against the present tracker structure and count expectation. If the tracker document format changes substantially, parser regression tests should be expanded beyond the current count check.

## New Findings

No new functional Apex test failures were discovered in the targeted suite. The new blocker is deploy-gate coverage on selected classes:

| Class                               | Coverage reported by Salesforce |
| ----------------------------------- | ------------------------------: |
| `QBCustomerToAccountSyncBatch`      |                         72.889% |
| `QBItemToProductSyncBatch`          |                         59.162% |
| `QBOWebhookService`                 |                         61.429% |
| `QBOInvoiceSyncQueueable`           |                         58.904% |
| `QuickbridgeConfigMigrationService` |                              0% |
| `IntegrationRetryPolicy`            |                         73.611% |
| `ErrorLogUtility`                   |                         69.492% |
| `ConnectorConfigService`            |                              0% |
| `QBVendorToAccountSyncBatch`        |                         71.429% |

Additional notes:

- The focused compile-only dry run succeeds, so there are no current compile blockers in the four-issue implementation set.
- The broader targeted dry run has 34 passing tests and 0 failing tests, so the remaining blocker is coverage, not failing assertions.
- `quickbridgeConfigPanel.js` has a large formatting diff from existing workspace work, but Prettier reports it is formatted.

## Recommended Next Order

1. Add focused coverage for `QBOInvoiceSyncQueueable`, `QBOWebhookService`, `QBItemToProductSyncBatch`, and `ConnectorConfigService`, because those are the largest deploy blockers.
2. Add compact branch coverage for `QuickbridgeConfigMigrationService`, especially normalized config migration diagnostics and legacy fallback boundaries.
3. Add targeted coverage for `ErrorLogUtility` canonical `Error_Log_Link__c` paths and `IntegrationRetryPolicy.exceptionForStatus`.
4. Rerun the same targeted dry run until coverage warnings clear.
5. Run a full `force-app` dry run after known unrelated stale-test and quick-action blockers are cleared.

## Appendix - Commands And Results

### Focused compile-only dry run

Command:

```powershell
sf project deploy start --dry-run --source-dir force-app/main/default/classes/QBOInvoiceSyncQueueable.cls --source-dir force-app/main/default/classes/QBOInvoiceSyncQueueableTest.cls --source-dir force-app/main/default/classes/QuickBooksBulkQueryService.cls --source-dir force-app/main/default/classes/QuickBooksBulkQueryServiceTest.cls --source-dir force-app/main/default/classes/QBCustomerToAccountSyncBatch.cls --source-dir force-app/main/default/classes/QBCustomerToAccountSyncBatchTest.cls --source-dir force-app/main/default/classes/QBVendorToAccountSyncBatch.cls --source-dir force-app/main/default/classes/QBVendorToAccountSyncBatchTest.cls --source-dir force-app/main/default/classes/QBItemToProductSyncBatch.cls --source-dir force-app/main/default/classes/QBItemToProductSyncBatchTest.cls --source-dir force-app/main/default/classes/IntegrationRetryPolicy.cls --source-dir force-app/main/default/classes/ErrorLogUtility.cls --test-level NoTestRun
```

Result:

- Status: `Succeeded`
- Deploy ID: `0Afal00002VcxAfCAJ`
- Components: `12/12`

### Targeted Apex dry run

Command:

```powershell
sf project deploy start --dry-run --source-dir force-app/main/default/classes/QBOInvoiceSyncQueueable.cls --source-dir force-app/main/default/classes/QBOInvoiceSyncQueueableTest.cls --source-dir force-app/main/default/classes/QBOWebhookService.cls --source-dir force-app/main/default/classes/QBOWebhookServiceTest.cls --source-dir force-app/main/default/classes/QuickBooksBulkQueryService.cls --source-dir force-app/main/default/classes/QuickBooksBulkQueryServiceTest.cls --source-dir force-app/main/default/classes/QBCustomerToAccountSyncBatch.cls --source-dir force-app/main/default/classes/QBCustomerToAccountSyncBatchTest.cls --source-dir force-app/main/default/classes/QBVendorToAccountSyncBatch.cls --source-dir force-app/main/default/classes/QBVendorToAccountSyncBatchTest.cls --source-dir force-app/main/default/classes/QBItemToProductSyncBatch.cls --source-dir force-app/main/default/classes/QBItemToProductSyncBatchTest.cls --source-dir force-app/main/default/classes/QuickBridgeRecordEngine.cls --source-dir force-app/main/default/classes/QuickBridgeRecordEngineTest.cls --source-dir force-app/main/default/classes/ErrorLogUtility.cls --source-dir force-app/main/default/classes/ErrorLogUtilityTest.cls --source-dir force-app/main/default/classes/IntegrationRetryPolicy.cls --source-dir force-app/main/default/classes/LockSafeDmlTest.cls --source-dir force-app/main/default/classes/ConnectorConfigService.cls --source-dir force-app/main/default/classes/QuickbridgeConfigMigrationService.cls --source-dir force-app/main/default/lwc/quickbridgeConfigPanel --test-level RunSpecifiedTests --tests QBOInvoiceSyncQueueableTest --tests QBOWebhookServiceTest --tests QuickBooksBulkQueryServiceTest --tests QBCustomerToAccountSyncBatchTest --tests QBVendorToAccountSyncBatchTest --tests QBItemToProductSyncBatchTest --tests QuickBridgeRecordEngineTest --tests ErrorLogUtilityTest --tests LockSafeDmlTest
```

Result:

- Status: `Failed`
- Deploy ID: `0Afal00002VcxCHCAZ`
- Components: `21/21`
- Tests: `34 passing`, `0 failing`
- Failure reason: per-class coverage warnings listed in New Findings.

### LWC formatting

Command:

```powershell
npx.cmd prettier --check force-app/main/default/lwc/quickbridgeConfigPanel/quickbridgeConfigPanel.js
```

Result:

- `All matched files use Prettier code style!`

### PDF count and generation

Command:

```powershell
& 'C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts/generate_issues_tracker_pdf.py 'C:\Users\USER\Downloads\QuickBridge_Issues_Tracker_3.docx' --output 'C:\Production Project\Quick Bridge\QuickBridge_Issues_Tracker_3.pdf' --print-counts
```

Result:

- `PARTIAL=7 OPEN=4 TOTAL=11`
