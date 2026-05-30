import { createElement } from "lwc";
import FieldMappingComponent from "c/fieldMappingComponent";
import getSalesforceObjects from "@salesforce/apex/FieldMappingController.getSalesforceObjects";
import getObjectFields from "@salesforce/apex/FieldMappingController.getObjectFields";
import getQuickBooksFields from "@salesforce/apex/FieldMappingController.getQuickBooksFields";
import getExistingMappings from "@salesforce/apex/FieldMappingController.getExistingMappings";
import getMappingDirectionAvailability from "@salesforce/apex/FieldMappingController.getMappingDirectionAvailability";
import getDraftOrderSetting from "@salesforce/apex/FieldMappingController.getDraftOrderSetting";

jest.mock(
  "@salesforce/apex/FieldMappingController.getSalesforceObjects",
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
  "@salesforce/apex/FieldMappingController.getExistingMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getMappingDirectionAvailability",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveFieldMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveChildFieldMappings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.getDraftOrderSetting",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FieldMappingController.saveDraftOrderSetting",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function appendComponent() {
  const element = createElement("c-field-mapping-component", {
    is: FieldMappingComponent
  });
  document.body.appendChild(element);
  return element;
}

describe("c-field-mapping-component reset", () => {
  beforeEach(() => {
    getSalesforceObjects.mockResolvedValue([
      { label: "Account", value: "Account" }
    ]);
    getObjectFields.mockResolvedValue([
      { label: "Name", value: "Name", type: "STRING" },
      { label: "Account Number", value: "AccountNumber", type: "STRING" }
    ]);
    getQuickBooksFields.mockResolvedValue([
      {
        label: "Display Name",
        value: "DisplayName",
        type: "STRING",
        required: true
      },
      { label: "Notes", value: "Notes", type: "STRING", required: false }
    ]);
    getExistingMappings.mockResolvedValue([
      {
        sfField: "Name",
        externalField: "DisplayName",
        syncDirection: "Two-Way"
      },
      {
        sfField: "AccountNumber",
        externalField: "Notes",
        syncDirection: "SF to QBO"
      }
    ]);
    getMappingDirectionAvailability.mockResolvedValue({
      inboundAllowed: true,
      outboundAllowed: true,
      twoWayAllowed: true,
      allDirectionsBlocked: false
    });
    getDraftOrderSetting.mockResolvedValue(false);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("clears editable mapping values instead of restoring saved values", async () => {
    const element = appendComponent();
    await flushPromises();
    await flushPromises();

    const sfFieldSelect = element.shadowRoot.querySelector(
      'tbody tr select[name="sfField"]'
    );
    expect(sfFieldSelect.value).toBe("Name");

    sfFieldSelect.value = "AccountNumber";
    sfFieldSelect.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    element.shadowRoot.querySelector(".btn-secondary").click();
    await flushPromises();
    element.shadowRoot.querySelector(".btn-danger").click();
    await flushPromises();

    const resetRows = element.shadowRoot.querySelectorAll("tbody tr");
    const resetSfFieldSelect = resetRows[0].querySelector(
      'select[name="sfField"]'
    );
    expect(resetRows).toHaveLength(1);
    expect(resetSfFieldSelect.value).toBe("");
    expect(getExistingMappings).toHaveBeenCalledTimes(1);
  });

  it("merges assistant suggestions into local rows without saving", async () => {
    const element = appendComponent();
    await flushPromises();
    await flushPromises();

    element.applyMappingSuggestions([
      {
        sfField: "AccountNumber",
        salesforceField: "AccountNumber",
        externalField: "Notes",
        syncDirection: "SF to QBO",
        required: false
      },
      {
        sfField: "Name",
        salesforceField: "Name",
        externalField: "DisplayName",
        syncDirection: "Two-Way",
        required: true
      }
    ]);
    await flushPromises();

    const rows = element.shadowRoot.querySelectorAll("tbody tr");
    expect(rows.length).toBe(2);
    expect(getExistingMappings).toHaveBeenCalledTimes(1);
  });
});
