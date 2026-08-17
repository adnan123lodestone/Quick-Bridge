# Post-install connection setup

QuickBridgeTLG deliberately does not package Auth Providers, External Credentials, or Named Credentials. Each subscriber must configure connector credentials in its own org after installation.

## QuickBooks

1. Create an OAuth Auth Provider using the subscriber's Intuit client ID and client secret. Do not commit either value to this repository.
2. Create an External Credential with OAuth, the required QuickBooks scopes, and a named principal linked to that Auth Provider.
3. Create the Named Credential used by the enabled QuickBooks configuration. Existing package code refers to `QuickBooksOnline`; sandbox-only configurations may use `QuickBookSandbox`.
4. Authorize the named principal, then update the active QuickBooks configuration to the appropriate Named Credential name.
5. Run the connector's connection validation and a non-production sync before enabling scheduled processing.

## Other connectors

Configure credentials, principals, endpoints, permissions, and connector configuration records in the subscriber org. Use least-privilege OAuth scopes and keep all client secrets, access tokens, and refresh tokens out of source control.
