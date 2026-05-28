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
});
