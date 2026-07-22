const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertNotContains(relativePath, pattern, message) {
  const source = read(relativePath);
  assert(!source.includes(pattern), `${relativePath}: ${message}`);
}

function assertAllowedLegacyConfigReferences() {
  const classesDir = path.join(root, "force-app/main/default/classes");
  const allowed = new Set([
    "CarrierRecordActionControllerTest.cls",
    "ConnectorConfigService.cls",
    "QuickbridgeLegacyConfigCompatibility.cls"
  ]);
  const offenders = [];
  for (const fileName of fs.readdirSync(classesDir)) {
    if (!fileName.endsWith(".cls")) continue;
    const source = fs.readFileSync(path.join(classesDir, fileName), "utf8");
    if (source.includes("Quickbridge_Config__mdt") && !allowed.has(fileName)) {
      offenders.push(fileName);
    }
  }
  assert(
    offenders.length === 0,
    `Quickbridge_Config__mdt references must stay in compatibility/migration/test classes only: ${offenders.join(", ")}`
  );
}

function assertNoPackagedCredentialDefaults() {
  const customMetadataDir = path.join(
    root,
    "force-app/main/default/customMetadata"
  );
  const sensitiveFields = [
    "APILoginId__c",
    "AuthorizeNet_API_Login_ID__c",
    "AuthorizeNet_Public_Client_Key__c",
    "AuthorizeNet_Webhook_Signing_Key__c",
    "ClientId__c",
    "FedEx_Account_Number__c",
    "FedEx_Client_Id__c",
    "FedEx_Client_Secret__c",
    "Password__c",
    "PayPal_ClientId__c",
    "PublicClientKey__c",
    "QuickBooks_Realm_ID__c",
    "QuickBooks_Verifier_Token__c",
    "Realm_ID__c",
    "Shopify_API_Key__c",
    "Shopify_API_Secret__c",
    "Shopify_Access_Token__c",
    "Shopify_Store_URL__c",
    "Store_URL__c",
    "Stripe_Publishable_Key__c",
    "Stripe_Webhook_Signing_Secret__c",
    "UPS_Account_Number__c",
    "UPS_Client_Id__c",
    "UPS_Client_Secret__c",
    "Username__c",
    "WebhookId__c",
    "WebhookSigningKey__c",
    "WebhookSigningSecret__c"
  ];
  const activeFields = [
    "Active__c",
    "AuthorizeNet_Active__c",
    "FedEx_Active__c",
    "Is_Active__c",
    "PayPal_Active__c",
    "QuickBooks_Is_Active__c",
    "Shopify_Is_Active__c",
    "Stripe_Active__c",
    "UPS_Active__c"
  ];
  const offenders = [];

  for (const fileName of fs.readdirSync(customMetadataDir)) {
    if (!fileName.endsWith(".md-meta.xml")) continue;
    const source = fs.readFileSync(
      path.join(customMetadataDir, fileName),
      "utf8"
    );

    for (const fieldName of sensitiveFields) {
      const pattern = new RegExp(
        `<field>${fieldName}</field>\\s*<value(?![^>]*xsi:nil=["']true["'])[^>]*>\\s*[^<\\s][^<]*</value>`,
        "s"
      );
      if (pattern.test(source)) {
        offenders.push(`${fileName}:${fieldName}`);
      }
    }

    const isConnectorConfigurationRecord =
      /^(?:Quickbridge_Config\.|AuthorizeNet_Config\.Default|PayPal_Config\.Default|QuickBooks_Config\.|Shopify_Config\.Default|Stripe_Config\.Default)/.test(
        fileName
      );
    if (isConnectorConfigurationRecord) {
      for (const fieldName of activeFields) {
        const pattern = new RegExp(
          `<field>${fieldName}</field>\\s*<value[^>]*>\\s*true\\s*</value>`,
          "s"
        );
        if (pattern.test(source)) {
          offenders.push(`${fileName}:${fieldName}=true`);
        }
      }
    }
  }

  assert(
    offenders.length === 0,
    `package custom metadata must not contain active connectors or credential defaults: ${offenders.join(", ")}`
  );
}

function assertNoOrgSpecificCredentialEndpoints() {
  const metadataDirectories = ["namedCredentials", "externalCredentials"];
  const offenders = [];
  for (const directoryName of metadataDirectories) {
    const directory = path.join(root, "force-app/main/default", directoryName);
    for (const fileName of fs.readdirSync(directory)) {
      const source = fs.readFileSync(path.join(directory, fileName), "utf8");
      if (/\.develop\.my\.salesforce\.com|orgfarm-/i.test(source)) {
        offenders.push(`${directoryName}/${fileName}`);
      }
    }
  }
  assert(
    offenders.length === 0,
    `package credentials must not point to an org-specific Salesforce endpoint: ${offenders.join(", ")}`
  );
}

function main() {
  assertNoPackagedCredentialDefaults();
  assertNoOrgSpecificCredentialEndpoints();
  assertNotContains(
    "force-app/main/default/classes/QuickBooksInvoiceBatch.cls",
    "'/invoice/'",
    "invoice batch update path must not use per-record invoice GET hydration"
  );
  assertNotContains(
    "force-app/main/default/classes/QuickBooksCreditMemoBatch.cls",
    "'/creditmemo/'",
    "credit memo batch update path must not use per-record credit memo GET hydration"
  );
  assertNotContains(
    "force-app/main/default/classes/QuickBooksPurchaseOrderBatch.cls",
    "'/purchaseorder/'",
    "purchase order batch update path must not use per-record purchase order GET hydration"
  );

  assertNotContains(
    "force-app/main/default/lwc/internalPaymentComponent/internalPaymentComponent.js",
    "FALLBACK_PAYMENT_PROVIDERS",
    "checkout providers must come from descriptors"
  );
  assertNotContains(
    "force-app/main/default/lwc/internalPaymentComponent/internalPaymentComponent.js",
    "isAuthorizeNetSelected",
    "payment parent must render by renderer type, not provider getter"
  );
  assertNotContains(
    "force-app/main/default/lwc/quickbridgeConfigPanel/quickbridgeConfigPanel.js",
    "LOGO_BY_CONNECTOR_KEY",
    "config panel logos must come from descriptors"
  );
  assertNotContains(
    "force-app/main/default/lwc/quickbridgeConfigPanel/quickbridgeConfigPanel.js",
    "isQboOrShopify",
    "scheduler visibility must be capability-driven"
  );
  assertNotContains(
    "force-app/main/default/lwc/quickbridgeConfigPanel/quickbridgeConfigPanel.html",
    "isQboOrShopify",
    "scheduler visibility must be capability-driven in the template"
  );

  const retryPolicy = read(
    "force-app/main/default/classes/IntegrationRetryPolicy.cls"
  );
  assert(
    !retryPolicy.includes("contains('timeout')") &&
      !retryPolicy.includes("contains('timed out')") &&
      !retryPolicy.includes("contains('read timed out')"),
    "retry policy must not classify arbitrary timeout-like text as retryable"
  );

  assertAllowedLegacyConfigReferences();

  const recordEngine = read(
    "force-app/main/default/classes/QuickBridgeRecordEngine.cls"
  );
  assert(
    recordEngine.includes(
      "Exactly one active canonical invoice pipeline target is required"
    ),
    "invoice pipeline must fail closed when canonical target metadata is invalid"
  );
  assert(
    fs.existsSync(
      path.join(
        root,
        "force-app/main/default/classes/ErrorLogLinkBackfillService.cls"
      )
    ),
    "error log link backfill service must exist"
  );

  const configPanel = read(
    "force-app/main/default/lwc/quickbridgeConfigPanel/quickbridgeConfigPanel.js"
  );
  assert(
    !configPanel.includes("QuickBridgeRuntimeGatewayService"),
    "admin config panel must not import runtime gateway APIs"
  );
  const checkout = read(
    "force-app/main/default/lwc/internalPaymentComponent/internalPaymentComponent.js"
  );
  assert(
    !checkout.includes("QuickBridgeAdminControlPlaneService") &&
      !checkout.includes("PaymentMetadataService"),
    "runtime checkout component must not import admin control-plane APIs"
  );

  console.log("QuickBridge permanent-fix static guardrails passed.");
}

main();
