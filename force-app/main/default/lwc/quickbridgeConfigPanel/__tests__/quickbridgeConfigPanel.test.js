import { createElement } from "lwc";
import fs from "fs";
import path from "path";
import QuickbridgeConfigPanel from "c/quickbridgeConfigPanel";
import verifyCredentialsAndGetGateways from "@salesforce/apex/QuickBridgeAdminControlPlaneService.verifyCredentialsAndGetGateways";
import getConnectorConfigs from "@salesforce/apex/PaymentMetadataService.getConnectorConfigs";
import getConfigPanelPreferences from "@salesforce/apex/PaymentMetadataService.getConfigPanelPreferences";
import getConnectorDescriptors from "@salesforce/apex/IntegrationConnectorRegistry.getConnectorDescriptors";
import revokeAdminSession from "@salesforce/apex/QuickBridgeAdminControlPlaneService.revokeAdminSession";

jest.mock(
  "@salesforce/apex/QuickBridgeAdminControlPlaneService.verifyCredentialsAndGetGateways",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PaymentMetadataService.getConnectorConfigs",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PaymentMetadataService.getConfigPanelPreferences",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/IntegrationConnectorRegistry.getConnectorDescriptors",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuickBridgeAdminControlPlaneService.revokeAdminSession",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/QuickBridge_Logo",
  () => ({ default: "quickbridge-logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/QuickBooks_Logo",
  () => ({ default: "/resource/QuickBooks_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/DHL_Logo",
  () => ({ default: "/resource/DHL_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/Shopify_Logo",
  () => ({ default: "/resource/Shopify_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/Stripe_Logo",
  () => ({ default: "/resource/Stripe_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/PayPal_Logo",
  () => ({ default: "/resource/PayPal_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/Authorize_Net_logo",
  () => ({ default: "/resource/Authorize_Net_logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/FedEx_Logo",
  () => ({ default: "/resource/FedEx_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/UPS_Logo",
  () => ({ default: "/resource/UPS_Logo" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/Klaviyo_Logo",
  () => ({ default: "/resource/Klaviyo_Logo" }),
  { virtual: true }
);

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function appendPanel() {
  const element = createElement("c-quickbridge-config-panel", {
    is: QuickbridgeConfigPanel
  });
  document.body.appendChild(element);
  return element;
}

function setInputValue(input, value) {
  input.value = value;
  input.dispatchEvent(new CustomEvent("input"));
}

describe("c-quickbridge-config-panel admin session", () => {
  beforeEach(() => {
    getConnectorDescriptors.mockResolvedValue([]);
    getConnectorConfigs.mockResolvedValue([]);
    getConfigPanelPreferences.mockResolvedValue({
      availableProductsVisible: true
    });
    revokeAdminSession.mockResolvedValue(true);
    sessionStorage.clear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    sessionStorage.clear();
  });

  it("keeps admin session tokens in memory only", async () => {
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    verifyCredentialsAndGetGateways.mockResolvedValue(
      JSON.stringify({
        status: "Success",
        sessionToken: "active-session-token",
        sessionExpiresAt: expiresAt
      })
    );

    let element = appendPanel();
    await flushPromises();

    setInputValue(
      element.shadowRoot.querySelector(".custom-input"),
      "admin@example.com"
    );
    element.shadowRoot
      .querySelectorAll(".pin-input")
      .forEach((input, index) => {
        input.value = String(index + 1);
      });
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit"));
    await flushPromises();

    expect(sessionStorage.length).toBe(0);
    expect(
      element.shadowRoot.querySelector(".nav-button.logout")
    ).not.toBeNull();

    getConnectorConfigs.mockClear();
    getConfigPanelPreferences.mockClear();
    document.body.removeChild(element);
    element = appendPanel();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".nav-button.logout")).toBeNull();
    expect(getConnectorConfigs).not.toHaveBeenCalled();
    expect(getConfigPanelPreferences).not.toHaveBeenCalled();
  });

  it("keeps connector logos and scheduler visibility descriptor-driven", () => {
    const source = fs.readFileSync(
      path.join(__dirname, "../quickbridgeConfigPanel.js"),
      "utf8"
    );
    const template = fs.readFileSync(
      path.join(__dirname, "../quickbridgeConfigPanel.html"),
      "utf8"
    );

    expect(source).not.toContain("LOGO_BY_CONNECTOR_KEY");
    expect(source).not.toContain("isQboOrShopify");
    expect(template).not.toContain("isQboOrShopify");
  });

  it("renders descriptor logo and scheduler capability for a new connector", async () => {
    getConnectorDescriptors.mockResolvedValue([
      {
        connectorKey: "newconnector",
        productKey: "newconnector",
        label: "New Connector",
        logoUrl: "/resource/newconnector",
        catalogActive: true,
        hasConfig: true,
        hasReporting: true,
        hasMapping: false,
        hasScheduler: true
      }
    ]);
    getConnectorConfigs.mockResolvedValue([
      {
        provider: "newconnector",
        active: true,
        fields: {},
        formValues: {},
        editableFields: [],
        fieldLabels: {}
      }
    ]);

    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    verifyCredentialsAndGetGateways.mockResolvedValue(
      JSON.stringify({
        status: "Success",
        sessionToken: "active-session-token",
        sessionExpiresAt: expiresAt
      })
    );

    const element = appendPanel();
    await flushPromises();

    setInputValue(
      element.shadowRoot.querySelector(".custom-input"),
      "admin@example.com"
    );
    element.shadowRoot
      .querySelectorAll(".pin-input")
      .forEach((input, index) => {
        input.value = String(index + 1);
      });
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit"));
    await flushPromises();

    const integrationsButton = [
      ...element.shadowRoot.querySelectorAll(".nav-button")
    ].find((button) => button.textContent.includes("Integrations"));
    integrationsButton.click();
    await flushPromises();

    const tileImage = element.shadowRoot.querySelector(".tile-logo-img");
    expect(tileImage.src).toContain("/resource/newconnector");
    element.shadowRoot.querySelector(".tile-card").click();
    await flushPromises();
    const schedulerButton = [
      ...element.shadowRoot.querySelectorAll(".nav-button")
    ].find((button) => button.textContent.includes("Scheduler"));
    expect(schedulerButton).not.toBeUndefined();
  });

  it("uses stable local brand logos for built-in products with missing or external descriptor images", async () => {
    getConnectorDescriptors.mockResolvedValue([
      {
        connectorKey: "qbo",
        productKey: "quickbooks",
        label: "QuickBooks",
        logoUrl: null,
        catalogActive: true,
        hasConfig: true,
        hasReporting: true,
        hasMapping: true
      },
      {
        connectorKey: "dhl",
        productKey: "dhl",
        label: "DHL",
        logoUrl: "",
        catalogActive: true,
        hasConfig: true,
        hasReporting: true,
        hasMapping: true
      },
      {
        connectorKey: "shopify",
        productKey: "shopify",
        label: "Shopify",
        logoUrl: "https://cdn.worldvectorlogo.com/logos/shopify.svg",
        catalogActive: true,
        hasConfig: true,
        hasReporting: true,
        hasMapping: true
      }
    ]);
    getConnectorConfigs.mockResolvedValue([]);

    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    verifyCredentialsAndGetGateways.mockResolvedValue(
      JSON.stringify({
        status: "Success",
        sessionToken: "active-session-token",
        sessionExpiresAt: expiresAt
      })
    );

    const element = appendPanel();
    await flushPromises();

    setInputValue(
      element.shadowRoot.querySelector(".custom-input"),
      "admin@example.com"
    );
    element.shadowRoot
      .querySelectorAll(".pin-input")
      .forEach((input, index) => {
        input.value = String(index + 1);
      });
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit"));
    await flushPromises();

    const integrationsButton = [
      ...element.shadowRoot.querySelectorAll(".nav-button")
    ].find((button) => button.textContent.includes("Integrations"));
    integrationsButton.click();
    await flushPromises();

    const tileImages = [
      ...element.shadowRoot.querySelectorAll(".tile-logo-img")
    ].map((image) => image.src);

    expect(tileImages.some((src) => src.includes("/resource/QuickBooks_Logo"))).toBe(true);
    expect(tileImages.some((src) => src.includes("/resource/DHL_Logo"))).toBe(true);
    expect(tileImages.some((src) => src.includes("/resource/Shopify_Logo"))).toBe(true);
    expect(tileImages).not.toContain(expect.stringContaining("worldvectorlogo"));
    expect(tileImages).not.toContain(expect.stringContaining("quickbridge-logo"));
  });
});
