import { createElement } from "lwc";
import FieldMappingComponent from "c/fieldMappingComponent";
import ShopifyFieldMappingComponent from "c/shopifyFieldMappingComponent";
import FedexFieldMappingComponent from "c/fedexFieldMappingComponent";
import UpsFieldMappingComponent from "c/upsFieldMappingComponent";
import DhlFieldMappingComponent from "c/dhlFieldMappingComponent";
import ConnectorFieldMappingComponent from "c/connectorFieldMappingComponent";

import getSalesforceObjectDiscovery from "@salesforce/apex/FieldMappingController.getSalesforceObjectDiscovery";
import getObjectFields from "@salesforce/apex/FieldMappingController.getObjectFields";
import getQuickBooksFields from "@salesforce/apex/FieldMappingController.getQuickBooksFields";
import getShopifyFields from "@salesforce/apex/FieldMappingController.getShopifyFields";
import getFedExFields from "@salesforce/apex/FieldMappingController.getFedExFields";
import getUPSFields from "@salesforce/apex/FieldMappingController.getUPSFields";
import getDHLFields from "@salesforce/apex/FieldMappingController.getDHLFields";
import getExistingMappings from "@salesforce/apex/FieldMappingController.getExistingMappings";
import getExistingFedExMappings from "@salesforce/apex/FieldMappingController.getExistingFedExMappings";
import getExistingUPSMappings from "@salesforce/apex/FieldMappingController.getExistingUPSMappings";
import getExistingDHLMappings from "@salesforce/apex/FieldMappingController.getExistingDHLMappings";
import getMappingDirectionAvailability from "@salesforce/apex/FieldMappingController.getMappingDirectionAvailability";
import getDraftOrderSetting from "@salesforce/apex/FieldMappingController.getDraftOrderSetting";
import getConnectorDescriptors from "@salesforce/apex/ConnectorRegistryService.getConnectorDescriptors";
import getExternalFields from "@salesforce/apex/FieldMappingController.getExternalFields";
import saveFieldMappings from "@salesforce/apex/FieldMappingController.saveFieldMappings";
import saveFedExFieldMappings from "@salesforce/apex/FieldMappingController.saveFedExFieldMappings";
import saveUPSFieldMappings from "@salesforce/apex/FieldMappingController.saveUPSFieldMappings";
import saveDHLFieldMappings from "@salesforce/apex/FieldMappingController.saveDHLFieldMappings";

jest.mock(
  "@salesforce/apex/FieldMappingController.getSalesforceObjectDiscovery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getObjectFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getQuickBooksFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getShopifyFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getFedExFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getUPSFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getDHLFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getExistingMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getExistingFedExMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getExistingUPSMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getExistingDHLMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getMappingDirectionAvailability",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getDraftOrderSetting",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ConnectorRegistryService.getConnectorDescriptors",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getExternalFields",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveFieldMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveFedExFieldMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveUPSFieldMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveDHLFieldMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const discovery = [
  {
    label: "Account",
    value: "Account",
    available: true,
    configured: true,
    configuredExternalObjects: ["Customer", "Campaign", "Shipment"]
  },
  {
    label: "Dynamic Object",
    value: "Dynamic_Object__c",
    available: true,
    configured: false,
    configuredExternalObjects: []
  }
];

const fields = [{ label: "Name", value: "Name", type: "STRING" }];
const externalFields = [
  { label: "External Name", value: "name", type: "STRING", required: false }
];

const flushPromises = () =>
  new Promise((resolve) => {
    // Jest must yield one macrotask for chained imperative Apex promises.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(resolve, 0);
  });

const selectFirstMappingRow = async (element) => {
  let externalSelect = element.shadowRoot.querySelector(
    'tbody select[name="externalField"]'
  );
  if (!externalSelect) {
    [externalSelect] = element.shadowRoot.querySelectorAll(
      "tbody select[data-row-id]"
    );
  }
  externalSelect.value = "name";
  externalSelect.dispatchEvent(new CustomEvent("change"));
  await flushPromises();

  let salesforceSelect = element.shadowRoot.querySelector(
    'tbody select[name="sfField"]'
  );
  if (!salesforceSelect) {
    [, salesforceSelect] = element.shadowRoot.querySelectorAll(
      "tbody select[data-row-id]"
    );
  }
  salesforceSelect.value = "Name";
  salesforceSelect.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
};

const saveButton = (element) =>
  [...element.shadowRoot.querySelectorAll("button")].find((button) =>
    button.textContent.includes("Save Mappings")
  );

describe("dynamic discovery mapping screens", () => {
  beforeEach(() => {
    getSalesforceObjectDiscovery.mockResolvedValue(discovery);
    getObjectFields.mockResolvedValue(fields);
    getQuickBooksFields.mockResolvedValue(externalFields);
    getShopifyFields.mockResolvedValue(externalFields);
    getFedExFields.mockResolvedValue(externalFields);
    getUPSFields.mockResolvedValue(externalFields);
    getDHLFields.mockResolvedValue(externalFields);
    getExistingMappings.mockResolvedValue([]);
    getExistingFedExMappings.mockResolvedValue([]);
    getExistingUPSMappings.mockResolvedValue([]);
    getExistingDHLMappings.mockResolvedValue([]);
    getMappingDirectionAvailability.mockResolvedValue({
      inboundAllowed: true,
      outboundAllowed: true,
      twoWayAllowed: true,
      allDirectionsBlocked: false
    });
    getDraftOrderSetting.mockResolvedValue(false);
    getConnectorDescriptors.mockResolvedValue([
      {
        connectorKey: "meta",
        productKey: "meta",
        aliases: "facebook,instagram",
        objectMappings: [
          {
            salesforceObject: "Account",
            externalObject: "Campaign",
            direction: "Bidirectional"
          }
        ]
      }
    ]);
    getExternalFields.mockResolvedValue(externalFields);
    saveFieldMappings.mockResolvedValue("Mappings Deployment Started");
    saveFedExFieldMappings.mockResolvedValue("Mappings Deployment Started");
    saveUPSFieldMappings.mockResolvedValue("Mappings Deployment Started");
    saveDHLFieldMappings.mockResolvedValue("Mappings Deployment Started");
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it.each([
    ["c-field-mapping-component", FieldMappingComponent],
    ["c-shopify-field-mapping-component", ShopifyFieldMappingComponent],
    ["c-fedex-field-mapping-component", FedexFieldMappingComponent],
    ["c-ups-field-mapping-component", UpsFieldMappingComponent],
    ["c-dhl-field-mapping-component", DhlFieldMappingComponent]
  ])(
    "persists a dynamically discovered object selection in %s",
    async (tagName, Component) => {
      const element = createElement(tagName, { is: Component });
      document.body.appendChild(element);
      await flushPromises();
      await flushPromises();

      let salesforceSelect =
        element.shadowRoot.querySelector("lightning-select");
      const optionValues = salesforceSelect.options.map(
        (option) => option.value
      );
      expect(optionValues).toContain("Dynamic_Object__c");

      salesforceSelect.dispatchEvent(
        new CustomEvent("change", {
          detail: { value: "Dynamic_Object__c" }
        })
      );
      await flushPromises();
      await flushPromises();

      salesforceSelect = element.shadowRoot.querySelector("lightning-select");
      expect(salesforceSelect.value).toBe("Dynamic_Object__c");
      expect(getObjectFields).toHaveBeenLastCalledWith({
        objectName: "Dynamic_Object__c"
      });
    }
  );

  it("adds dynamic selectors to the generic Meta and NetSuite mapper", async () => {
    const element = createElement("c-connector-field-mapping-component", {
      is: ConnectorFieldMappingComponent
    });
    element.connectorKey = "meta";
    element.connectorLabel = "Meta";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    const salesforceSelect =
      element.shadowRoot.querySelector("lightning-select");
    const externalSelect =
      element.shadowRoot.querySelectorAll("lightning-select")[1];
    expect(salesforceSelect.options.map((option) => option.value)).toContain(
      "Dynamic_Object__c"
    );
    expect(externalSelect.options.map((option) => option.value)).toContain(
      "Campaign"
    );
  });

  it("keeps configured defaults and requires an explicit entity for an unknown QBO pair", async () => {
    const element = createElement("c-field-mapping-component", {
      is: FieldMappingComponent
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    let salesforceSelect = element.shadowRoot.querySelector("lightning-select");
    let externalSelect =
      element.shadowRoot.querySelectorAll("lightning-select")[1];
    expect(externalSelect.value).toBe("Customer");

    salesforceSelect.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "Dynamic_Object__c" }
      })
    );
    await flushPromises();
    await flushPromises();
    salesforceSelect = element.shadowRoot.querySelector("lightning-select");
    expect(salesforceSelect.value).toBe("Dynamic_Object__c");
    externalSelect = element.shadowRoot.querySelectorAll("lightning-select")[1];
    expect(externalSelect.value).toBe("");
    expect(element.shadowRoot.querySelector(".btn-primary").disabled).toBe(
      true
    );

    externalSelect.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Customer" } })
    );
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("not registered yet");
  });

  it("allows a dynamic Meta object after explicit external selection and shows the mapping-only warning", async () => {
    const element = createElement("c-connector-field-mapping-component", {
      is: ConnectorFieldMappingComponent
    });
    element.connectorKey = "meta";
    element.connectorLabel = "Meta";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    let salesforceSelect = element.shadowRoot.querySelector("lightning-select");
    salesforceSelect.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "Dynamic_Object__c" }
      })
    );
    await flushPromises();
    salesforceSelect = element.shadowRoot.querySelector("lightning-select");
    expect(salesforceSelect.value).toBe("Dynamic_Object__c");

    const externalSelect =
      element.shadowRoot.querySelectorAll("lightning-select")[1];
    expect(externalSelect.value).toBe("");
    externalSelect.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Campaign" } })
    );
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("not registered yet");
  });

  it("clears the pending-registration warning after a QBO mapping save is queued", async () => {
    const element = createElement("c-field-mapping-component", {
      is: FieldMappingComponent
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    element.shadowRoot.querySelector("lightning-select").dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "Dynamic_Object__c" }
      })
    );
    await flushPromises();
    await flushPromises();
    element.shadowRoot
      .querySelectorAll("lightning-select")[1]
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "Customer" } })
      );
    await flushPromises();
    await flushPromises();

    await selectFirstMappingRow(element);
    saveButton(element).click();
    await flushPromises();
    await flushPromises();

    expect(saveFieldMappings).toHaveBeenCalledWith(
      expect.objectContaining({
        integration: "qbonline",
        sfObject: "Dynamic_Object__c",
        qbObject: "Customer",
        mappingsJson: expect.stringContaining('"sfField":"Name"')
      })
    );
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });

  it("clears the pending-registration warning after a Shopify mapping save is queued", async () => {
    const element = createElement("c-shopify-field-mapping-component", {
      is: ShopifyFieldMappingComponent
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    element.shadowRoot.querySelector("lightning-select").dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "Dynamic_Object__c" }
      })
    );
    await flushPromises();
    await flushPromises();
    element.shadowRoot
      .querySelectorAll("lightning-select")[1]
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "Customer" } })
      );
    await flushPromises();
    await flushPromises();

    await selectFirstMappingRow(element);
    saveButton(element).click();
    await flushPromises();

    expect(saveFieldMappings).toHaveBeenCalledWith(
      expect.objectContaining({
        integration: "shopify",
        sfObject: "Dynamic_Object__c",
        qbObject: "Customer",
        mappingsJson: expect.stringContaining('"sfField":"Name"')
      })
    );
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });

  it("keeps the pending-registration warning when a save fails", async () => {
    saveFieldMappings.mockRejectedValueOnce({
      body: { message: "Save failed" }
    });
    const element = createElement("c-connector-field-mapping-component", {
      is: ConnectorFieldMappingComponent
    });
    element.connectorKey = "meta";
    element.connectorLabel = "Meta";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    element.shadowRoot.querySelector("lightning-select").dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "Dynamic_Object__c" }
      })
    );
    await flushPromises();
    element.shadowRoot
      .querySelectorAll("lightning-select")[1]
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "Campaign" } })
      );
    await flushPromises();
    await flushPromises();

    await selectFirstMappingRow(element);
    saveButton(element).click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("not registered yet");
  });

  it.each([
    [
      "c-fedex-field-mapping-component",
      FedexFieldMappingComponent,
      saveFedExFieldMappings
    ],
    [
      "c-ups-field-mapping-component",
      UpsFieldMappingComponent,
      saveUPSFieldMappings
    ],
    [
      "c-dhl-field-mapping-component",
      DhlFieldMappingComponent,
      saveDHLFieldMappings
    ]
  ])(
    "registers an unknown carrier pair after saving in %s",
    async (tagName, Component, saveMock) => {
      const element = createElement(tagName, { is: Component });
      document.body.appendChild(element);
      await flushPromises();
      await flushPromises();

      element.shadowRoot.querySelector("lightning-select").dispatchEvent(
        new CustomEvent("change", {
          detail: { value: "Dynamic_Object__c" }
        })
      );
      await flushPromises();
      await flushPromises();
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent
      ).toContain("not registered yet");

      await selectFirstMappingRow(element);
      saveButton(element).click();
      await flushPromises();

      expect(saveMock).toHaveBeenCalledWith(
        expect.objectContaining({ sfObject: "Dynamic_Object__c" })
      );
      expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    }
  );

  it("blocks shipment-only carrier actions when no shipment object is configured", async () => {
    getSalesforceObjectDiscovery.mockResolvedValue([
      {
        label: "Account",
        value: "Account",
        available: true,
        configured: true,
        configuredExternalObjects: ["Customer"]
      }
    ]);
    const element = createElement("c-fedex-field-mapping-component", {
      is: FedexFieldMappingComponent
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    element.shadowRoot
      .querySelector('[data-action="voidShipment"]')
      .dispatchEvent(new CustomEvent("click"));
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("shipment object is unavailable");
    expect(
      element.shadowRoot.querySelector(".selector-action button").disabled
    ).toBe(true);
  });

  it("renders a safe empty state when discovery fails", async () => {
    getSalesforceObjectDiscovery.mockRejectedValue(
      new Error("Discovery unavailable")
    );
    const element = createElement("c-field-mapping-component", {
      is: FieldMappingComponent
    });
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(
      element.shadowRoot.querySelector("lightning-select").options
    ).toHaveLength(0);
  });
});
