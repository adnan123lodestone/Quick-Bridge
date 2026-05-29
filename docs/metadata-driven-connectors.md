# Metadata-Driven Connectors

QuickBridge now treats `ConnectorRegistryService` as the authoritative connector catalog. New runtime/admin code should read connector descriptors, capabilities, config fields, and object mappings from registry metadata first, then use `LegacyConnectorRegistryFallback` only for compatibility with existing QuickBooks, Shopify, payment, and carrier behavior.

## Add a Connector

1. Create an `Integration_Connector__mdt` record with:
   - `Connector_Key__c`: stable lowercase key, for example `avalara`
   - `Product_Key__c`: entitlement/product key
   - `Provider_Label__c`, `Category__c`, aliases, display order, and feature flags
   - legacy config record/active/expiry fields only if the connector still needs `Quickbridge_Config__mdt` compatibility
2. Create `Integration_Connector_Capability__mdt` records for each runtime surface:
   - `payment.checkout` -> `PaymentProviderAdapter`
   - `scheduler.operation` -> `ScheduledOperationAdapter`
   - `carrier.operation` -> `ICarrierAdapter`
   - `work.<OperationKey>` -> `IntegrationWorkHandler`
3. Create `Connector_Config_Field__mdt` records for non-secret admin/display fields.
   - Mark token, password, secret, CVV, private key, and client secret fields as secret.
   - Secret values must be stored as Named Credential / External Credential references, protected metadata, encrypted fields, or server-side session/token state.
4. Create `Connector_Instance__c` and `Connector_Config_Value__c` rows for org-specific activation, environment, lifecycle dates, health, Named Credential references, and non-secret values.
5. Create `Integration_Object_Map__mdt` or `Integration_Entity_Definition__c` rows for Salesforce object to external entity relationships.
6. Add or reuse an adapter/handler class only when the connector requires new executable behavior. Adding a connector that uses existing adapters should be metadata-only.

## Current Built-In Capabilities

The repository includes capability metadata for:

- Stripe, PayPal, and Authorize.Net checkout adapters.
- QuickBooks and Shopify scheduler adapters.
- FedEx and UPS carrier adapters.
- QuickBooks work handlers for account, product, invoice, credit memo, and purchase order upserts.
- Shopify work handlers for customer, order, and product upserts.

## Legacy Compatibility

These paths intentionally remain until existing customers migrate their metadata/config:

- `Quickbridge_Config__mdt` reads in payment, carrier, Shopify, QuickBooks, entitlement, and webhook services.
- Provider-specific runtime services such as `StripePaymentService`, `PayPalPaymentService`, `AuthorizeNetPaymentService`, QuickBooks batches, Shopify batches, FedEx/UPS adapters, and existing webhook handlers.
- Field definition fallback data in `FieldMappingController` for QuickBooks, Shopify, FedEx, and UPS where mapping metadata is incomplete.
- Existing QBO/Shopify scheduler wrapper methods and logical schedule names.

New connector work should not add new provider-specific fields to `Quickbridge_Config__mdt`; use connector metadata, instance records, config values, and credential references instead.
