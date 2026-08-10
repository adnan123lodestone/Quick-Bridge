import {
  buildObjectOptions,
  findObjectOption,
  firstAvailableObject,
  isConfiguredPair,
  normalizeObjectApiName,
  registerConfiguredPair,
  selectConfiguredExternalObject
} from "c/mappingObjectDiscovery";

const discoveredObjects = [
  {
    label: "Account",
    value: "Account",
    available: true,
    configured: true,
    configuredExternalObjects: ["Customer", "Vendor"]
  },
  {
    label: "Dynamic Object",
    value: "Dynamic_Object__c",
    available: true,
    configured: false,
    configuredExternalObjects: []
  },
  {
    label: "Missing Object (Unavailable)",
    value: "Missing_Object__c",
    available: false,
    configured: true,
    configuredExternalObjects: ["Customer"]
  }
];

describe("mapping object discovery helpers", () => {
  it("preserves availability and configuration state", () => {
    const options = buildObjectOptions(discoveredObjects, "Account");

    expect(options).toHaveLength(3);
    expect(options[0].selected).toBe(true);
    expect(options[2].disabled).toBe(true);
    expect(firstAvailableObject(options)).toBe("Account");
  });

  it("matches namespaced managed-package object names", () => {
    expect(normalizeObjectApiName("QuickBridgeTLG__Invoice__c")).toBe(
      "invoice__c"
    );
    expect(
      findObjectOption(
        buildObjectOptions(discoveredObjects),
        "pkg__Dynamic_Object__c"
      ).value
    ).toBe("Dynamic_Object__c");
  });

  it("uses configured defaults and leaves unknown objects explicit", () => {
    const options = buildObjectOptions(discoveredObjects);
    const externalOptions = [
      { value: "Customer" },
      { value: "Vendor" },
      { value: "Invoice" }
    ];

    expect(
      selectConfiguredExternalObject(
        options,
        "Account",
        externalOptions,
        "Vendor"
      )
    ).toBe("Vendor");
    expect(
      selectConfiguredExternalObject(
        options,
        "Dynamic_Object__c",
        externalOptions,
        "Customer"
      )
    ).toBe("");
    expect(isConfiguredPair(options, "Account", "Customer")).toBe(true);
    expect(isConfiguredPair(options, "Dynamic_Object__c", "Customer")).toBe(
      false
    );
  });

  it("marks a newly registered pair without mutating other options", () => {
    const options = buildObjectOptions(discoveredObjects);
    const registered = registerConfiguredPair(
      options,
      "pkg__Dynamic_Object__c",
      "Invoice"
    );

    expect(isConfiguredPair(registered, "Dynamic_Object__c", "Invoice")).toBe(
      true
    );
    expect(findObjectOption(registered, "Account")).toEqual(
      findObjectOption(options, "Account")
    );
    expect(isConfiguredPair(options, "Dynamic_Object__c", "Invoice")).toBe(
      false
    );
  });
});
