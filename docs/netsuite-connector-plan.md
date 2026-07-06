# NetSuite Connector

QuickBridge implements NetSuite as a metadata-driven connector with connector key `netsuite` and aliases `ns`, `oracle_netsuite`, and `oracle-netsuite`.

Phase 1 is intentionally read-focused:

- Validate a configured NetSuite connection.
- Read Customer records into Account and Contact.
- Read Item records into Product2.
- Register Sales Order, Invoice, Payment, and Fulfillment as roadmap mapping domains without enabling write flows.

No NetSuite-specific fields are added to `Quickbridge_Config__mdt`. Org-specific values belong in `Connector_Instance__c` and `Connector_Config_Value__c`, with credentials referenced by Named Credential and External Credential names.

## Metadata

The connector is registered through:

- `Integration_Connector.NetSuite`
- `Integration_Product_Default.NetSuite`
- `Integration_Connector_Capability.NetSuite_Scheduler`
- `Integration_Connector_Capability.NetSuite_Work_CustomerSync`
- `Integration_Connector_Capability.NetSuite_Work_ItemSync`
- `Connector_Config_Field.NetSuite_*`
- `Integration_Object_Map.NetSuite_Customer_Account`
- `Integration_Object_Map.NetSuite_Customer_Contact`
- `Integration_Object_Map.NetSuite_Item_Product`

The admin tile, config panel, scheduler entry points, mapping selector, and connector descriptor surfaces should render from those records rather than hardcoded NetSuite UI logic.

## Required Org Setup

Create the Salesforce credential records in the target org before activating sync:

1. Create an External Credential for the NetSuite auth strategy.
2. Create a Named Credential that points to the NetSuite REST Web Services host.
3. Grant the QuickBridge integration/admin permission set access to the credential principal.
4. Create or activate a `Connector_Instance__c` row for `netsuite`.
5. Save these config values:
   - `account_id`
   - `environment`
   - `rest_web_services_url`
   - `suiteql_url`
   - `named_credential_name`
   - `auth_type`
   - optional default subsidiary, currency, price level, location, department, and class
   - customer and item sync toggles
   - polling interval

Do not store NetSuite consumer secrets, token secrets, account-specific internal IDs, script IDs, deployment IDs, or raw access tokens in source control.

## Authentication

Phase 1 uses Token-Based Authentication support classes and stores only credential references in QuickBridge config. The implementation isolates signing and credential resolution so OAuth 2.0 can be added later without changing mapping metadata or work routing.

`NetSuiteRequestSigner` provides deterministic OAuth 1.0a HMAC-SHA256 signing primitives for tests and future auth strategy expansion. Runtime callouts should prefer Named Credential authentication wherever possible.

## Sync Behavior

Customer sync reads these NetSuite fields through SuiteQL:

- `id`
- `entityid`
- `companyname`
- `email`
- `phone`
- `firstname`
- `lastname`
- `lastmodifieddate`

Item sync reads:

- `id`
- `itemid`
- `displayname`
- `salesdescription`
- `baseprice`
- `isinactive`
- `lastmodifieddate`

Salesforce writes use existing external ID fields when present:

- `Account.External_Id__c`
- `Contact.External_Id__c`
- `Product2.External_Id__c`

Values are namespaced as `netsuite:<internalId>` or `netsuite:contact:<internalId>` to avoid collisions with other connectors. If a target external ID field is removed or unavailable, write sync must be blocked and logged rather than adding unmanaged replacement fields.

## Error And Audit

NetSuite errors are normalized into user-safe categories before logging:

- authentication
- permission
- validation
- duplicate
- not found
- governance or rate limit
- timeout
- serialization
- mapping

Admin actions should create `QuickBridge_Admin_Audit__c` rows for config save, credential validation, activation, manual sync, mapping changes, sync failures, retry actions, and scheduled sync dispatch.

## Permissions

Admin operations must continue to enforce:

- `View_QuickBridge`
- `Manage_QuickBridge`
- `Run_QuickBridge_Sync`

Connection validation requires manage access. Runtime sync is server-side and should not expose credential material or NetSuite payload secrets to LWC.

## Phase 2 Candidates

- OAuth 2.0 auth strategy.
- Bidirectional Customer and Item write-back.
- Sales Order, Invoice, Payment, and Fulfillment transaction flows.
- Webhook or RESTlet ingestion where customer environments require it.
- Dedicated subsidiary, department, class, location, and price-level mapping controls.
