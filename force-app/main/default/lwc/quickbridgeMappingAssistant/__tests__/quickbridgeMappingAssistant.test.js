import { createElement } from "lwc";
import QuickbridgeMappingAssistant from "c/quickbridgeMappingAssistant";
import reviewMappings from "@salesforce/apex/QuickBridgeMappingAssistantController.reviewMappings";
import suggestMappings from "@salesforce/apex/QuickBridgeMappingAssistantController.suggestMappings";
import generateCodexPrompt from "@salesforce/apex/QuickBridgeMappingAssistantController.generateCodexPrompt";

jest.mock(
  "@salesforce/apex/QuickBridgeMappingAssistantController.reviewMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuickBridgeMappingAssistantController.suggestMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuickBridgeMappingAssistantController.generateCodexPrompt",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function appendComponent(props = {}) {
  const element = createElement("c-quickbridge-mapping-assistant", {
    is: QuickbridgeMappingAssistant
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const REVIEW_RESULT = {
  healthScore: 82,
  status: "Good",
  risks: [
    {
      severity: "Warning",
      message: "Duplicate external field mapping.",
      salesforceField: "Name",
      externalField: "DisplayName",
      suggestedFix: "Keep one mapping."
    }
  ],
  missingRequiredFields: [
    {
      externalField: "PrimaryEmailAddr.Address",
      externalFieldLabel: "Primary Email",
      externalFieldType: "STRING",
      required: true,
      suggestedSalesforceField: "PersonEmail",
      reason: "Email synonym match."
    }
  ],
  suggestions: [
    {
      connectorKey: "qbonline",
      salesforceObject: "Account",
      externalObject: "Customer",
      salesforceField: "Name",
      salesforceFieldLabel: "Account Name",
      salesforceFieldType: "STRING",
      externalField: "DisplayName",
      externalFieldLabel: "Display Name",
      externalFieldType: "STRING",
      syncDirection: "Two-Way",
      confidence: 95,
      confidenceLabel: "High",
      reason: "Exact label match.",
      required: true,
      canApply: true
    },
    {
      connectorKey: "qbonline",
      salesforceObject: "Account",
      externalObject: "Customer",
      salesforceField: "Phone",
      salesforceFieldLabel: "Phone",
      salesforceFieldType: "PHONE",
      externalField: "PrimaryPhone.FreeFormNumber",
      externalFieldLabel: "Primary Phone",
      externalFieldType: "STRING",
      syncDirection: "Two-Way",
      confidence: 64,
      confidenceLabel: "Medium",
      reason: "Phone synonym match.",
      required: false,
      canApply: true
    }
  ]
};

describe("c-quickbridge-mapping-assistant", () => {
  beforeEach(() => {
    reviewMappings.mockResolvedValue(REVIEW_RESULT);
    suggestMappings.mockResolvedValue(REVIEW_RESULT.suggestions);
    generateCodexPrompt.mockResolvedValue("Generated deterministic fix prompt");
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders empty state without selected objects", async () => {
    const element = appendComponent();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "Select a Salesforce object and external object to analyze mappings."
    );
    expect(reviewMappings).not.toHaveBeenCalled();
  });

  it("renders health, missing fields, risks, and suggestions", async () => {
    const element = appendComponent({
      connectorKey: "qbonline",
      connectorLabel: "QuickBooks Online",
      salesforceObject: "Account",
      externalObject: "Customer",
      allowApply: true,
      currentMappings: []
    });
    await flushPromises();

    const text = element.shadowRoot.textContent;
    expect(text).toContain("82");
    expect(text).toContain("Good");
    expect(text).toContain("Primary Email");
    expect(text).toContain("Duplicate external field mapping.");
    expect(text).toContain("Display Name");
  });

  it("emits selected suggestions without saving", async () => {
    const element = appendComponent({
      connectorKey: "qbonline",
      connectorLabel: "QuickBooks Online",
      salesforceObject: "Account",
      externalObject: "Customer",
      allowApply: true,
      currentMappings: []
    });
    const handler = jest.fn();
    element.addEventListener("applysuggestions", handler);
    await flushPromises();

    const checkbox = element.shadowRoot.querySelector('input[type="checkbox"]');
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event("change"));
    await flushPromises();
    const applyButton = [...element.shadowRoot.querySelectorAll("button")].find(
      (button) => button.textContent.includes("Apply Selected")
    );
    applyButton.click();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.suggestions).toHaveLength(1);
  });

  it("applies only high confidence suggestions", async () => {
    const element = appendComponent({
      connectorKey: "qbonline",
      salesforceObject: "Account",
      externalObject: "Customer",
      allowApply: true,
      currentMappings: []
    });
    const handler = jest.fn();
    element.addEventListener("applysuggestions", handler);
    await flushPromises();

    const highButton = [...element.shadowRoot.querySelectorAll("button")].find(
      (button) => button.textContent.includes("Apply High Confidence")
    );
    highButton.click();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.suggestions).toHaveLength(1);
    expect(handler.mock.calls[0][0].detail.suggestions[0].confidenceLabel).toBe(
      "High"
    );
  });

  it("shows generated fix prompt", async () => {
    const element = appendComponent({
      connectorKey: "qbonline",
      salesforceObject: "Account",
      externalObject: "Customer",
      currentMappings: []
    });
    await flushPromises();

    const promptButton = [...element.shadowRoot.querySelectorAll("button")].find(
      (button) => button.textContent.includes("Generate Fix Prompt")
    );
    promptButton.click();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "Generated deterministic fix prompt"
    );
  });

  it("renders safe inline error when Apex fails", async () => {
    reviewMappings.mockRejectedValueOnce({ body: { message: "Apex failed" } });
    const element = appendComponent({
      connectorKey: "qbonline",
      salesforceObject: "Account",
      externalObject: "Customer",
      currentMappings: []
    });
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("Apex failed");
  });
});
