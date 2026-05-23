# QuickBridge Issues Tracker 3.0 Closure Matrix

Date: 2026-05-23
Branch: `codex/quickbridge-issues-3-resolution`

## Resolved In This Branch

| Area | Resolution | Evidence |
| --- | --- | --- |
| Klaviyo plaintext token usage | Added `KlaviyoAuthService` and migrated Klaviyo list/profile/event/campaign-member callouts to `callout:Klaviyo_API` without Apex `Authorization` headers. Added Named Credential and External Credential metadata shells without secret values. | Scoped Salesforce dry-run compiled the Klaviyo service, batches, metadata, Named Credential, and External Credential. Klaviyo tests assert Named Credential endpoints and no Apex auth header. |
| Klaviyo campaign member synchronous work | `KlaviyoCampaignMembersService.addCampaignMembers()` now validates input, enqueues `KlaviyoCampaignMembersAsync`, and returns a queued job response. | `KlaviyoCampaignMembersServiceTest` updated for `202` and returned job id. |
| Authorize.Net webhook bypass | Removed the runtime HMAC bypass so Authorize.Net webhook requests require real `X-ANET-Signature` verification. | `PaymentWebhookRestResource` compiled in scoped dry-run. |
| PayPal unauthenticated webhook handling | PayPal webhook events now fail closed with `503` until verification is configured, instead of accepting unauthenticated events. | `PaymentWebhookRestResource` compiled in scoped dry-run. |
| Admin session token persistence | Removed `sessionStorage` token persistence and reload restoration from `quickbridgeConfigPanel`; admin tokens are memory-only. | LWC bundle compiled in scoped dry-run. Repo lint still has unrelated pre-existing panel lint violations. |
| QuickBooks sandbox fallback | Removed `QuickBridgeTLG__QuickBookSandbox` fallback; missing Realm ID or Named Credential is an explicit configuration error. | `QuickBooksAuthHandlerTest` covers endpoint building and missing Named Credential behavior. |
| Retry registry | Added `RetryHandler`, `QBORetryHandler`, `ShopifyRetryHandler`, registry capability records, and allowlist entries. `RetryDispatcher` now resolves handlers through connector capability metadata. | `RetryDispatcherTest` covers registered handler resolution. |
| Retry policy status classification | Added HTTP status-aware retry/rate-limit classification while preserving existing message-based overloads. | `LockSafeDmlTest` covers status retry policy behavior. |
| Scheduler registry metadata | Added `Integration_Type__c` and `Counts_Toward_Schedule_Limit__c` fields to `Integration_Connector__mdt`, populated connector records, and routed scheduler type/key mapping through the registry. | Scoped dry-run compiled new metadata fields, connector records, scheduler router/controller changes. Live query shows one active `QuickBridge Integration Heartbeat` Cron job. |
| Klaviyo scheduler capability | Added Klaviyo connector metadata and `KlaviyoScheduledOperationAdapter` for heartbeat-driven profile/list/event sync modes. | Scoped dry-run compiled adapter and capability metadata. |
| Carrier adapter factory | `CarrierAdapterFactory` now resolves `carrier.operation` adapters through connector capability metadata and the allowlist. | Scoped dry-run compiled factory and allowlist changes. |
| QuickBooks vendor/item N+1 cleanup | Vendor and item batches now pass serialized query payloads from `start()` into `execute()` and only hydrate per-record for legacy raw-id payloads. | Batch tests assert `/vendor/` and `/item/` hydration endpoints are not called during normal query-payload execution. |
| System-managed integration products | Added `Integration_Product__c.System_Managed__c`, a validation rule protecting system-managed products, and seed service marking seeded products as system-managed. | Scoped dry-run compiled field, validation rule, and seed service changes. |

## Existing Source Already Covered

| Area | Existing Source Evidence |
| --- | --- |
| NEW-013 legacy registry fallback | `LegacyConnectorRegistryFallback.cls` and `ConnectorAdapterAllowlist.cls` already exist; this branch extends them with integration type, schedule-limit, scheduler, and retry handler metadata support. |
| Error log link object | `ErrorLogUtility` already creates `Error_Log_Link__c` rows through generic link handling, with existing lookup compatibility retained. |

## Validation Notes

| Check | Result |
| --- | --- |
| Scoped Salesforce dry-run, no tests | Succeeded for the changed source set before the final test assertion cleanup. |
| Scoped Salesforce dry-run, specified tests | Source compiled with zero component errors. Targeted tests were reduced from 7 failures to 1 org-metadata-sensitive field assertion before final cleanup; remaining expected blocker is per-class coverage warnings on selected classes unless broader tests are included. |
| Full `force-app` dry-run | Blocked by unrelated existing metadata/test issues: invalid `QuickActionLabel` values in community case quick actions and a stale `QuickBridgeArchitectureRefactorTest` scheduler signature expectation. |
| Scheduler query | One `QuickBridge Integration Heartbeat` Cron job is active and waiting; no connector-specific `QuickBridge%` Cron jobs were returned. |
| LWC lint | Repo-wide lint remains red from pre-existing `quickbridgeConfigPanel` issues such as restricted `setTimeout`, empty block, and `confirm`; session storage references introduced by the old token persistence path are removed. |

## Remaining Phases

| Area | Remaining Work |
| --- | --- |
| Normalized config authority | Complete migration so `Connector_Instance__c` and `Connector_Config_Value__c` are authoritative after `QuickbridgeConfigMigrationService`, with legacy MDT only as documented migration fallback. |
| Payment metadata/config UI maps | Remove remaining static connector maps from `PaymentMetadataService` and `quickbridgeConfigPanel`; derive aliases, start fields, and expiry fields fully from descriptors. |
| Product defaults metadata | Move seed definitions to `Integration_Product_Default__mdt` and add an admin reseed action. |
| Control-plane decomposition | Split `quickbridgeConfigPanel` into shell, settings, mapping, scheduler, reporting, and renewal child components. |
| Runtime/control-plane separation | Further separate checkout/runtime reads from admin login/session/config actions. |
| Internal payment component | Refactor to provider configs keyed by connector key, dynamic ordering, provider renderer modes, and unknown hosted provider handling. |
| Invoice pipeline | Add metadata-driven invoice pipeline targets, process all active targets, and cache describe resolution. |
| Sharing audit | Finish class-by-class sharing review for runtime versus admin contexts. |
| Full org validation | Re-run full `force-app` dry-run after unrelated quick action metadata and stale architecture test blockers are corrected. |
