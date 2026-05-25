import { createElement } from "lwc";
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

const SESSION_STORAGE_KEY = "quickbridge.adminSession";

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

  it("keeps a valid admin session across page reloads", async () => {
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

    expect(sessionStorage.getItem(SESSION_STORAGE_KEY)).toContain(
      "active-session-token"
    );
    expect(
      element.shadowRoot.querySelector(".nav-button.logout")
    ).not.toBeNull();

    document.body.removeChild(element);
    element = appendPanel();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".nav-button.logout")
    ).not.toBeNull();
    expect(getConnectorConfigs).toHaveBeenCalled();
    expect(getConfigPanelPreferences).toHaveBeenCalled();
  });
});
