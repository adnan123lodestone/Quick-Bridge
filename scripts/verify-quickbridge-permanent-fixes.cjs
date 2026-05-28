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

function main() {
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
