import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSalesforceObjects from "@salesforce/apex/FieldMappingController.getSalesforceObjects";
import getObjectFields from "@salesforce/apex/FieldMappingController.getObjectFields";
import getShopifyFields from "@salesforce/apex/FieldMappingController.getShopifyFields";
import getExistingMappings from "@salesforce/apex/FieldMappingController.getExistingMappings";
import saveFieldMappings from "@salesforce/apex/FieldMappingController.saveFieldMappings";
import clearFieldMappings from "@salesforce/apex/FieldMappingController.clearFieldMappings";

export default class ShopifyFieldMappingComponent extends LightningElement {
  @track selectedIntegration = "shopify";
  @track selectedSFObject = "Account";
  @track selectedShopifyObject = "Customer";
  @track mappingRows = [];
  @track rowCounter = 1;
  @track sfObjectOptions = [];
  @track sfFieldOptions = [];
  @track shopifyFieldOptions = [];
  @track isLoading = true;
  @track showResetConfirm = false;

  @track syncDirectionBaseOptions = [
    { label: "SF to Shopify", value: "SF to Shopify" },
    { label: "Shopify to SF", value: "Shopify to SF" },
    { label: "Two-Way", value: "Two-Way" }
  ];

  @track shopifyObjectOptions = [
    { label: "Customer", value: "Customer", selected: true },
    { label: "Order", value: "Order", selected: false },
    { label: "Product", value: "Product", selected: false },
    { label: "Line Item", value: "LineItem", selected: false }
  ];

  // Only expose the SF objects relevant for Shopify
  shopifyAllowedSFObjects = ["Account", "Order", "Product2", "OrderItem"];

  connectedCallback() {
    this.loadInitialData();
  }

  loadInitialData() {
    this.loadSalesforceObjects()
      .then(() =>
        this.handleSalesforceObjectChange({
          target: { value: this.selectedSFObject }
        })
      )
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  loadSalesforceObjects() {
    return getSalesforceObjects().then((result) => {
      // Filter to only Shopify-supported objects
      const filtered = result.filter((obj) =>
        this.shopifyAllowedSFObjects.includes(obj.value)
      );
      this.sfObjectOptions = filtered.map((obj) => ({
        label: obj.label,
        value: obj.value,
        selected: obj.value === this.selectedSFObject
      }));
    });
  }

  loadObjectFields(objectName) {
    return getObjectFields({ objectName }).then((result) => {
      this.sfFieldOptions = (result || []).map((field) => ({
        ...field,
        type: this.normalizeType(field.type)
      }));
    });
  }

  loadShopifyFields() {
    return getShopifyFields({
      sfObject: this.selectedSFObject,
      shopifyObject: this.selectedShopifyObject
    }).then((result) => {
      this.shopifyFieldOptions = (result || []).map((field) => ({
        ...field,
        type: this.normalizeType(field.type),
        required: Boolean(field.required)
      }));
    });
  }

  updateShopifyObjectSelection(sfObject) {
    const objectMap = {
      Account: "Customer",
      Order: "Order",
      Product2: "Product",
      OrderItem: "LineItem"
    };
    this.selectedShopifyObject = objectMap[sfObject] || "Customer";
    this.shopifyObjectOptions = this.shopifyObjectOptions.map((opt) => ({
      ...opt,
      selected: opt.value === this.selectedShopifyObject
    }));
  }

  buildMappingRows(savedMappings) {
    const requiredFields = this.shopifyFieldOptions.filter(
      (field) => field.required
    );
    const rows = [];
    let counter = 1;

    requiredFields.forEach((field) => {
      const existingMapping = savedMappings.find(
        (mapping) => mapping.externalField === field.value
      );
      rows.push({
        id: counter++,
        sfField: existingMapping?.sfField || "",
        externalField: field.value,
        syncDirection: existingMapping?.syncDirection || "Two-Way",
        isMandatory: true
      });
    });

    savedMappings.forEach((mapping) => {
      const isRequired = requiredFields.some(
        (field) => field.value === mapping.externalField
      );
      if (!isRequired) {
        rows.push({
          id: counter++,
          sfField: mapping.sfField,
          externalField: mapping.externalField,
          syncDirection: mapping.syncDirection || "Two-Way",
          isMandatory: false
        });
      }
    });

    if (rows.length === 0) {
      rows.push({
        id: counter++,
        sfField: "",
        externalField: "",
        syncDirection: "Two-Way",
        isMandatory: false
      });
    }

    this.mappingRows = rows;
    this.rowCounter = counter;
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleSalesforceObjectChange(event) {
    const objectName = event.target ? event.target.value : event.detail.value;
    this.selectedSFObject = objectName;
    this.isLoading = true;

    this.updateShopifyObjectSelection(objectName);
    this.sfObjectOptions = this.sfObjectOptions.map((opt) => ({
      ...opt,
      selected: opt.value === objectName
    }));

    // loadShopifyFields must complete first so this.shopifyFieldOptions is set
    // before buildMappingRows reads it. loadObjectFields and getExistingMappings
    // don't depend on shopifyFieldOptions, so they run in parallel after.
    this.loadShopifyFields()
      .then(() =>
        Promise.all([
          this.loadObjectFields(objectName),
          getExistingMappings({
            integration: this.selectedIntegration,
            sfObject: objectName,
            qbObject: null
          })
        ])
      )
      .then(([, savedMappings]) => {
        this.buildMappingRows(savedMappings || []);
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  handleShopifyObjectChange(event) {
    this.selectedShopifyObject = event.target.value;
    this.shopifyObjectOptions = this.shopifyObjectOptions.map((opt) => ({
      ...opt,
      selected: opt.value === this.selectedShopifyObject
    }));
    this.isLoading = true;

    // loadShopifyFields must complete first so this.shopifyFieldOptions is set
    // before buildMappingRows reads it.
    this.loadShopifyFields()
      .then(() =>
        getExistingMappings({
          integration: this.selectedIntegration,
          sfObject: this.selectedSFObject,
          qbObject: null
        })
      )
      .then((savedMappings) => {
        this.buildMappingRows(savedMappings || []);
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  updateRowDropdowns() {
    this.mappingRows = this.mappingRows.map((row) => {
      const shopifyField = this.shopifyFieldOptions.find(
        (option) => option.value === row.externalField
      );
      const shopifyType = shopifyField ? shopifyField.type : null;
      const availableSfOptions = shopifyType
        ? this.sfFieldOptions.filter((option) =>
            this.isTypeMatch(option.type, shopifyType)
          )
        : [];
      const currentSfFieldValid =
        row.sfField &&
        availableSfOptions.some((option) => option.value === row.sfField);

      return {
        ...row,
        sfField: currentSfFieldValid ? row.sfField : "",
        isSFFieldDisabled: !row.isMandatory && !row.externalField,
        fieldBorderClass:
          row.syncDirection === "Two-Way"
            ? "custom-select-table sync-dir-two-way"
            : "custom-select-table sync-dir-one-way",
        externalFieldOptions: this.shopifyFieldOptions.map((option) => ({
          ...option,
          selected: option.value === row.externalField
        })),
        sfFieldOptions: availableSfOptions.map((option) => ({
          ...option,
          selected: option.value === row.sfField
        })),
        syncDirectionOptions: this.syncDirectionBaseOptions.map((option) => ({
          ...option,
          selected: option.value === row.syncDirection
        }))
      };
    });
  }

  handleAddRow() {
    this.mappingRows = [
      ...this.mappingRows,
      {
        id: this.rowCounter++,
        sfField: "",
        externalField: "",
        syncDirection: "Two-Way",
        isMandatory: false
      }
    ];
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleRemoveRow(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    this.mappingRows = this.mappingRows.filter((row) => row.id !== rowId);
    if (this.mappingRows.length === 0) {
      this.handleAddRow();
      return;
    }
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleSFFieldChange(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    const value = event.target.value;
    this.mappingRows = this.mappingRows.map((row) => {
      return row.id === rowId ? { ...row, sfField: value } : row;
    });
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleExternalFieldChange(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    const value = event.target.value;

    this.mappingRows = this.mappingRows.map((row) => {
      if (row.id !== rowId) return row;
      const shopifyField = this.shopifyFieldOptions.find(
        (option) => option.value === value
      );
      const sfField = this.sfFieldOptions.find(
        (option) => option.value === row.sfField
      );
      const keepSfField =
        shopifyField &&
        sfField &&
        this.isTypeMatch(sfField.type, shopifyField.type);
      return {
        ...row,
        externalField: value,
        sfField: value && keepSfField ? row.sfField : ""
      };
    });
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleSyncDirectionChange(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    const value = event.target.value;
    this.mappingRows = this.mappingRows.map((row) => {
      return row.id === rowId ? { ...row, syncDirection: value } : row;
    });
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleSave() {
    const duplicateExternalFields = this.getDuplicateExternalFields();
    if (duplicateExternalFields.length > 0) {
      this.showToast(
        "Validation Error",
        "Each Shopify field can only be mapped once.",
        "error"
      );
      return;
    }

    const missingRequiredRow = this.mappingRows.find(
      (row) => row.isMandatory && (!row.externalField || !row.sfField)
    );
    if (missingRequiredRow) {
      this.showToast(
        "Validation Error",
        "Map a Salesforce field to every required Shopify field.",
        "error"
      );
      return;
    }

    const rowsToSave = this.mappingRows
      .filter((row) => row.sfField && row.externalField)
      .map((row) => {
        return {
          sfField: row.sfField,
          externalField: row.externalField,
          syncDirection: row.syncDirection
        };
      });

    this.isLoading = true;
    saveFieldMappings({
      integration: this.selectedIntegration,
      sfObject: this.selectedSFObject,
      qbObject: this.selectedShopifyObject,
      mappingsJson: JSON.stringify(rowsToSave)
    })
      .then((result) => {
        this.isLoading = false;
        this.showToast("Success", result, "success");
      })
      .catch((error) => {
        this.isLoading = false;
        this.showToast("Error", error.body?.message || error.message, "error");
      });
  }

  handleResetClick() {
    this.showResetConfirm = true;
  }

  handleResetCancel() {
    this.showResetConfirm = false;
  }

  handleResetConfirm() {
    this.showResetConfirm = false;
    this.isLoading = true;
    clearFieldMappings({
      integration: this.selectedIntegration,
      sfObject: this.selectedSFObject
    })
      .then(() => {
        this.showToast(
          "Success",
          "Mappings cleared. Changes will be fully reflected after the metadata deployment completes.",
          "success"
        );
        this.resetMappingRows();
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  resetMappingRows() {
    const requiredShopifyFields = this.shopifyFieldOptions.filter(
      (field) => field.required
    );
    let counter = 1;

    const rows = requiredShopifyFields.map((field) => ({
      id: counter++,
      sfField: "",
      externalField: field.value,
      syncDirection: "Two-Way",
      isMandatory: true
    }));

    if (rows.length === 0) {
      rows.push({
        id: counter++,
        sfField: "",
        externalField: "",
        syncDirection: "Two-Way",
        isMandatory: false
      });
    }

    this.mappingRows = rows;
    this.rowCounter = counter;
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  @api
  applyMappingSuggestions(suggestions = []) {
    const rows = [...this.mappingRows];
    let changed = false;

    suggestions.forEach((suggestion) => {
      const sfField = suggestion.salesforceField || suggestion.sfField;
      const externalField = suggestion.externalField;
      if (!sfField || !externalField) return;
      if (
        rows.some(
          (row) =>
            row.sfField === sfField && row.externalField === externalField
        )
      )
        return;

      const existingExternal = rows.find(
        (row) => row.externalField === externalField
      );
      if (existingExternal) {
        if (!existingExternal.sfField) {
          existingExternal.sfField = sfField;
          existingExternal.syncDirection =
            suggestion.syncDirection || existingExternal.syncDirection;
          changed = true;
        }
        return;
      }

      rows.push({
        id: this.rowCounter++,
        sfField,
        externalField,
        syncDirection: suggestion.syncDirection || "Two-Way",
        isMandatory: suggestion.required === true
      });
      changed = true;
    });

    if (changed) {
      this.mappingRows = rows;
      this.updateRowDropdowns();
      this.notifyMappingContextChange();
    }
  }

  notifyMappingContextChange() {
    this.dispatchEvent(
      new CustomEvent("mappingcontextchange", {
        bubbles: true,
        composed: true,
        detail: {
          connectorKey: this.selectedIntegration,
          connectorLabel: "Shopify",
          salesforceObject: this.selectedSFObject,
          externalObject: this.selectedShopifyObject,
          syncDirection: null,
          allowApply: true,
          mappings: this.mappingRows.map((row) => ({
            sfField: row.sfField,
            externalField: row.externalField,
            syncDirection: row.syncDirection,
            isMandatory: row.isMandatory
          }))
        }
      })
    );
  }

  getDuplicateExternalFields() {
    const seen = new Set();
    const duplicates = [];
    this.mappingRows.forEach((row) => {
      if (!row.externalField) return;
      if (seen.has(row.externalField)) {
        duplicates.push(row.externalField);
        return;
      }
      seen.add(row.externalField);
    });
    return duplicates;
  }

  normalizeType(type) {
    const value = (type || "").toUpperCase();
    if (
      [
        "CURRENCY",
        "DOUBLE",
        "INTEGER",
        "PERCENT",
        "DECIMAL",
        "LONG",
        "NUMBER"
      ].includes(value)
    )
      return "NUMBER";
    if (["DATE", "DATETIME"].includes(value)) return "DATE";
    if (value === "BOOLEAN") return "BOOLEAN";
    return "STRING";
  }

  isTypeMatch(sfType, shopifyType) {
    if (!shopifyType || !sfType) return false;
    return this.normalizeType(sfType) === this.normalizeType(shopifyType);
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}