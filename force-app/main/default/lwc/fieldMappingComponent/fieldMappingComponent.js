import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSalesforceObjectDiscovery from "@salesforce/apex/FieldMappingController.getSalesforceObjectDiscovery";
import getObjectFields from "@salesforce/apex/FieldMappingController.getObjectFields";
import getQuickBooksFields from "@salesforce/apex/FieldMappingController.getQuickBooksFields";
import getExistingMappings from "@salesforce/apex/FieldMappingController.getExistingMappings";
import getMappingDirectionAvailability from "@salesforce/apex/FieldMappingController.getMappingDirectionAvailability";
import saveFieldMappings from "@salesforce/apex/FieldMappingController.saveFieldMappings";
import saveChildFieldMappings from "@salesforce/apex/FieldMappingController.saveChildFieldMappings";
import getDraftOrderSetting from "@salesforce/apex/FieldMappingController.getDraftOrderSetting";
import saveDraftOrderSetting from "@salesforce/apex/FieldMappingController.saveDraftOrderSetting";
import clearFieldMappings from "@salesforce/apex/FieldMappingController.clearFieldMappings";
import {
  buildObjectOptions,
  firstAvailableObject,
  isConfiguredPair,
  registerConfiguredPair,
  selectConfiguredExternalObject
} from "c/mappingObjectDiscovery";

export default class FieldMappingComponent extends LightningElement {
  @track selectedIntegration = "qbonline";
  @track selectedSFObject = "Account";
  @track selectedQBObject = "Customer";
  @track mappingRows = [];
  @track rowCounter = 1;
  @track sfObjectOptions = [];
  @track sfFieldOptions = [];
  @track qbFieldOptions = [];
  @track isLoading = true;
  @track showResetConfirm = false;
  @track directionAvailability = {
    inboundAllowed: true,
    outboundAllowed: true,
    twoWayAllowed: true,
    allDirectionsBlocked: false,
    message: ""
  };
  @track syncDirectionBaseOptions = [
    { label: "SF to QBO", value: "SF to QBO" },
    { label: "QBO to SF", value: "QBO to SF" },
    { label: "Two-Way", value: "Two-Way" }
  ];

  @track qbObjectOptions = [
    { label: "Customer", value: "Customer", selected: false },
    { label: "Vendor", value: "Vendor", selected: false },
    { label: "Item", value: "Item", selected: false },
    { label: "Invoice", value: "Invoice", selected: false },
    { label: "Credit Memo", value: "CreditMemo", selected: false },
    { label: "Purchase Order", value: "PurchaseOrder", selected: false },
    { label: "Tax Code", value: "TaxCode", selected: false },
    { label: "Estimate", value: "Estimate", selected: false }
  ];

  // --- Child Mapping Variables ---
  @track childSfObject = "";
  @track childQbObject = "InvoiceLine";
  @track childMappingRows = [];
  @track childSfFieldOptions = [];
  @track childQbFieldOptions = [];
  @track showChildMapping = false;
  @track mapDraftAsEstimate = false;

  connectedCallback() {
    this.loadInitialData();

    getDraftOrderSetting()
      .then((result) => {
        this.mapDraftAsEstimate = result;
      })
      .catch((error) => {
        console.error("Error loading draft order setting:", error);
      });
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
    return getSalesforceObjectDiscovery({
      connectorKey: this.selectedIntegration
    }).then((result) => {
      this.sfObjectOptions = buildObjectOptions(result, this.selectedSFObject);
      if (
        !this.sfObjectOptions.some(
          (option) =>
            option.value === this.selectedSFObject && option.available !== false
        )
      ) {
        this.selectedSFObject = firstAvailableObject(this.sfObjectOptions);
      }
      this.updateQBObjectSelection(this.selectedSFObject);
      this.sfObjectOptions = this.sfObjectOptions.map((option) => ({
        ...option,
        selected: option.value === this.selectedSFObject
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

  loadQuickBooksFields() {
    if (!this.selectedQBObject) {
      this.qbFieldOptions = [];
      return Promise.resolve();
    }
    return getQuickBooksFields({
      sfObject: this.selectedSFObject,
      qbObject: this.selectedQBObject
    }).then((result) => {
      this.qbFieldOptions = (result || []).map((field) => ({
        ...field,
        type: this.normalizeType(field.type),
        required: Boolean(field.required),
        inboundAllowed: field.inboundAllowed !== false,
        outboundAllowed: field.outboundAllowed !== false
      }));
    });
  }

  loadDirectionAvailability(objectName = this.selectedSFObject) {
    return getMappingDirectionAvailability({
      integration: this.selectedIntegration,
      sfObject: objectName
    }).then((result) => {
      this.directionAvailability = {
        inboundAllowed: result?.inboundAllowed !== false,
        outboundAllowed: result?.outboundAllowed !== false,
        twoWayAllowed: result?.twoWayAllowed !== false,
        allDirectionsBlocked: result?.allDirectionsBlocked === true,
        message: result?.message || "",
        otherIntegrationLabel: result?.otherIntegrationLabel || "",
        inboundConflictDirection: result?.inboundConflictDirection || "",
        outboundConflictDirection: result?.outboundConflictDirection || ""
      };
    });
  }

  updateQBObjectSelection(sfObject) {
    this.selectedQBObject = selectConfiguredExternalObject(
      this.sfObjectOptions,
      sfObject,
      this.qbObjectOptions,
      this.selectedQBObject
    );
    this.qbObjectOptions = this.qbObjectOptions.map((opt) => ({
      ...opt,
      selected: opt.value === this.selectedQBObject
    }));
  }

  buildMappingRows(savedMappings) {
    const requiredQbFields = this.qbFieldOptions.filter(
      (field) => field.required
    );
    const rows = [];
    let counter = 1;

    requiredQbFields.forEach((field) => {
      const existingMapping = savedMappings.find(
        (mapping) => mapping.externalField === field.value
      );
      rows.push({
        id: counter++,
        sfField: existingMapping?.sfField || "",
        externalField: field.value,
        syncDirection: this.getAvailableDirectionValue(
          existingMapping?.syncDirection
        ),
        isMandatory: true
      });
    });

    savedMappings.forEach((mapping) => {
      const isRequired = requiredQbFields.some(
        (field) => field.value === mapping.externalField
      );
      // Skip saved rows whose QBO field does not exist for the currently selected
      // QBO object (e.g. a legacy Customer mapping viewed on the Vendor tab). These
      // would otherwise render as a blank "-- None --" row.
      const isValidForObject = this.qbFieldOptions.some(
        (field) => field.value === mapping.externalField
      );
      if (!isRequired && isValidForObject) {
        rows.push({
          id: counter++,
          sfField: mapping.sfField,
          externalField: mapping.externalField,
          syncDirection: this.getAvailableDirectionValue(mapping.syncDirection),
          isMandatory: false
        });
      }
    });

    if (rows.length === 0) {
      rows.push({
        id: counter++,
        sfField: "",
        externalField: "",
        syncDirection: this.getDefaultSyncDirection(),
        isMandatory: false
      });
    }

    this.mappingRows = rows;
    this.rowCounter = counter;
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleSalesforceObjectChange(event) {
    const objectName = event.detail?.value ?? event.target?.value ?? "";
    this.selectedSFObject = objectName;
    this.isLoading = true;

    this.updateQBObjectSelection(objectName);
    this.sfObjectOptions = this.sfObjectOptions.map((opt) => ({
      ...opt,
      selected: opt.value === objectName
    }));

    const childObjectMap = {
      Order: "OrderItem",
      OrderSummary: "OrderItemSummary",
      Quote: "QuoteLineItem",
      QuickBridgeTLG__Invoice__c: "QuickBridgeTLG__Invoice_Line__c",
      Invoice__c: "Invoice_Line__c",
      QuickBridgeTLG__Credit_Memo__c: "QuickBridgeTLG__Credit_Memo_Line__c",
      Credit_Memo__c: "Credit_Memo_Line__c",
      QuickBridgeTLG__Purchase_Order__c:
        "QuickBridgeTLG__Purchase_Order_Line__c",
      Purchase_Order__c: "Purchase_Order_Line__c"
    };

    const childQbObjectMap = {
      OrderItem: "InvoiceLine",
      OrderItemSummary: "InvoiceLine",
      QuoteLineItem: "EstimateLine",
      QuickBridgeTLG__Invoice_Line__c: "InvoiceLine",
      Invoice_Line__c: "InvoiceLine",
      QuickBridgeTLG__Credit_Memo_Line__c: "CreditMemoLine",
      Credit_Memo_Line__c: "CreditMemoLine",
      QuickBridgeTLG__Purchase_Order_Line__c: "PurchaseOrderLine",
      Purchase_Order_Line__c: "PurchaseOrderLine"
    };

    if (childObjectMap[this.selectedSFObject]) {
      this.childSfObject = childObjectMap[this.selectedSFObject];
      this.childQbObject =
        childQbObjectMap[this.childSfObject] || "InvoiceLine";
      this.showChildMapping = true;
      this.loadChildFields();
    } else {
      this.showChildMapping = false;
      this.childSfObject = "";
      this.childQbObject = "InvoiceLine";
      this.childMappingRows = [];
    }

    Promise.all([
      this.loadObjectFields(objectName),
      this.loadQuickBooksFields(),
      this.loadDirectionAvailability(objectName),
      this.selectedQBObject
        ? getExistingMappings({
            integration: this.selectedIntegration,
            sfObject: objectName,
            qbObject: this.selectedQBObject
          })
        : Promise.resolve([])
    ])
      .then(([, , , savedMappings]) => {
        this.buildMappingRows(savedMappings || []);
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  handleQBObjectChange(event) {
    this.selectedQBObject = event.detail?.value ?? event.target?.value ?? "";
    this.qbObjectOptions = this.qbObjectOptions.map((opt) => ({
      ...opt,
      selected: opt.value === this.selectedQBObject
    }));
    this.isLoading = true;

    Promise.all([
      this.loadQuickBooksFields(),
      this.loadDirectionAvailability(this.selectedSFObject),
      getExistingMappings({
        integration: this.selectedIntegration,
        sfObject: this.selectedSFObject,
        qbObject: this.selectedQBObject
      })
    ])
      .then(([, , savedMappings]) => {
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
      const qbField = this.qbFieldOptions.find(
        (option) => option.value === row.externalField
      );
      const allowedDirections = this.getAllowedSyncDirectionOptions(qbField);
      const qbType = qbField ? qbField.type : null;
      const availableSfOptions = qbType
        ? this.sfFieldOptions.filter((option) =>
            this.isTypeMatch(option.type, qbType)
          )
        : [];
      const currentSfFieldValid =
        row.sfField &&
        availableSfOptions.some((option) => option.value === row.sfField);
      const selectedDirection = this.getAvailableDirectionValue(
        row.syncDirection,
        allowedDirections
      );

      return {
        ...row,
        sfField: currentSfFieldValid ? row.sfField : "",
        syncDirection: selectedDirection,
        fieldBorderClass:
          selectedDirection === "Two-Way"
            ? "custom-select-table sync-dir-two-way"
            : "custom-select-table sync-dir-one-way",
        isSFFieldDisabled: !row.isMandatory && !row.externalField,
        isExternalFieldBlank: !row.externalField,
        isSfFieldBlank: !row.sfField,
        externalFieldOptions: this.qbFieldOptions.map((option) => ({
          ...option,
          selected: option.value === row.externalField
        })),
        sfFieldOptions: availableSfOptions.map((option) => ({
          ...option,
          selected: option.value === row.sfField
        })),
        syncDirectionOptions: allowedDirections.map((option) => ({
          ...option,
          selected: option.value === selectedDirection
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
        syncDirection: this.getDefaultSyncDirection(),
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
      if (row.id !== rowId) {
        return row;
      }

      const qbField = this.qbFieldOptions.find(
        (option) => option.value === value
      );
      const sfField = this.sfFieldOptions.find(
        (option) => option.value === row.sfField
      );
      const keepSfField =
        qbField && sfField && this.isTypeMatch(sfField.type, qbField.type);

      return {
        ...row,
        externalField: value,
        sfField: value && keepSfField ? row.sfField : ""
      };
    });
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  async handleSave() {
    if (this.isMappingBlocked) {
      this.showToast(
        "Validation Error",
        this.directionConflictMessage,
        "error"
      );
      return;
    }

    const duplicateExternalFields = this.getDuplicateExternalFields();
    if (duplicateExternalFields.length > 0) {
      this.showToast(
        "Validation Error",
        "Each QuickBooks field can only be mapped once.",
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
        "Map a Salesforce field to every required QuickBooks field.",
        "error"
      );
      return;
    }

    const rowsToSave = this.mappingRows
      .filter((row) => row.sfField && row.externalField)
      .map((row) => ({
        sfField: row.sfField,
        externalField: row.externalField,
        syncDirection: row.syncDirection
      }));

    this.isLoading = true;
    saveFieldMappings({
      integration: this.selectedIntegration,
      sfObject: this.selectedSFObject,
      qbObject: this.selectedQBObject,
      mappingsJson: JSON.stringify(rowsToSave)
    })
      .then((result) => {
        if (rowsToSave.length) {
          this.sfObjectOptions = registerConfiguredPair(
            this.sfObjectOptions,
            this.selectedSFObject,
            this.selectedQBObject
          );
        }
        this.isLoading = false;
        this.showToast("Success", result, "success");
      })
      .catch((error) => {
        this.isLoading = false;
        this.showToast("Error", error.body?.message || error.message, "error");
      });

    if (this.showChildMapping && this.childMappingRows.length) {
      const childRowsToSave = this.childMappingRows
        .filter((row) => row.sfField && row.qbField)
        .map((row) => ({
          sfField: row.sfField,
          qbField: row.qbField,
          syncDirection: row.syncDirection
        }));
      if (childRowsToSave.length) {
        await saveChildFieldMappings({
          integration: this.selectedIntegration,
          sfObject: this.childSfObject,
          qbObject: this.childQbObject,
          mappingsJson: JSON.stringify(childRowsToSave)
        });
      }
    }
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
    const clearCalls = [
      clearFieldMappings({
        integration: this.selectedIntegration,
        sfObject: this.selectedSFObject
      })
    ];
    if (this.showChildMapping && this.childSfObject) {
      clearCalls.push(
        clearFieldMappings({
          integration: this.selectedIntegration,
          sfObject: this.childSfObject
        })
      );
    }
    Promise.all(clearCalls)
      .then(() => {
        this.showToast(
          "Success",
          "Mappings cleared. Changes will be fully reflected after the metadata deployment completes.",
          "success"
        );
        this.resetParentMappingRows();
        if (this.showChildMapping) {
          this.resetChildMappingRows();
        }
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  resetParentMappingRows() {
    const requiredQbFields = this.qbFieldOptions.filter(
      (field) => field.required
    );
    const defaultDirection = this.getDefaultSyncDirection();
    let counter = 1;

    const rows = requiredQbFields.map((field) => ({
      id: counter++,
      sfField: "",
      externalField: field.value,
      syncDirection: defaultDirection,
      isMandatory: true
    }));

    if (rows.length === 0) {
      rows.push({
        id: counter++,
        sfField: "",
        externalField: "",
        syncDirection: defaultDirection,
        isMandatory: false
      });
    }

    this.mappingRows = rows;
    this.rowCounter = counter;
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  getDuplicateExternalFields() {
    const seen = new Set();
    const duplicates = [];

    this.mappingRows.forEach((row) => {
      if (!row.externalField) {
        return;
      }
      if (seen.has(row.externalField)) {
        duplicates.push(row.externalField);
        return;
      }
      seen.add(row.externalField);
    });

    return duplicates;
  }

  get isMappingBlocked() {
    return (
      !this.selectedSFObject ||
      !this.selectedQBObject ||
      this.directionAvailability?.allDirectionsBlocked === true
    );
  }

  get isQBObjectBlank() {
    return !this.selectedQBObject;
  }

  get qbObjectSelectOptions() {
    return [
      { label: "Select a QuickBooks object", value: "" },
      ...this.qbObjectOptions.map(({ label, value }) => ({ label, value }))
    ];
  }

  get showMappingOnlyWarning() {
    return (
      Boolean(this.selectedSFObject && this.selectedQBObject) &&
      !isConfiguredPair(
        this.sfObjectOptions,
        this.selectedSFObject,
        this.selectedQBObject
      )
    );
  }

  get mappingOnlyWarning() {
    return "This pair is not registered yet. Saving valid field mappings will register it. Automated QuickBooks processing remains limited to supported runtime objects.";
  }

  get directionConflictMessage() {
    if (!this.selectedQBObject) {
      return "Select a QuickBooks object before configuring field mappings.";
    }
    return this.directionAvailability?.message || "";
  }

  getAllowedSyncDirectionOptions(qbField = null) {
    const allowed = this.syncDirectionBaseOptions.filter((option) => {
      if (option.value === "Two-Way") {
        return (
          this.directionAvailability.twoWayAllowed &&
          qbField?.inboundAllowed !== false &&
          qbField?.outboundAllowed !== false
        );
      }
      if (option.value === "QBO to SF") {
        return (
          this.directionAvailability.inboundAllowed &&
          qbField?.inboundAllowed !== false
        );
      }
      if (option.value === "SF to QBO") {
        return (
          this.directionAvailability.outboundAllowed &&
          qbField?.outboundAllowed !== false
        );
      }
      return true;
    });
    return allowed.length > 0
      ? allowed
      : [{ label: "No available direction", value: "" }];
  }

  getDefaultSyncDirection(
    allowedDirections = this.getAllowedSyncDirectionOptions()
  ) {
    const twoWay = allowedDirections.find(
      (option) => option.value === "Two-Way"
    );
    return twoWay ? twoWay.value : allowedDirections[0]?.value || "";
  }

  getAvailableDirectionValue(
    value,
    allowedDirections = this.getAllowedSyncDirectionOptions()
  ) {
    const defaultValue = this.getDefaultSyncDirection(allowedDirections);
    const currentValue = value || defaultValue;
    return allowedDirections.some((option) => option.value === currentValue)
      ? currentValue
      : defaultValue;
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
    ) {
      return "NUMBER";
    }
    if (["DATE", "DATETIME"].includes(value)) {
      return "DATE";
    }
    if (value === "BOOLEAN") {
      return "BOOLEAN";
    }
    return "STRING";
  }

  isTypeMatch(sfType, qbType) {
    if (!qbType || !sfType) {
      return false;
    }
    const normSf = this.normalizeType(sfType);
    const normQb = this.normalizeType(qbType);
    return normSf === normQb;
  }

  get showDraftOrderCheckbox() {
    return this.showChildMapping && this.selectedSFObject === "Order";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
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

  @api
  applyMappingSuggestions(suggestions = []) {
    const rows = [...this.mappingRows];
    let changed = false;

    suggestions.forEach((suggestion) => {
      const sfField = suggestion.salesforceField || suggestion.sfField;
      const externalField = suggestion.externalField;
      if (!sfField || !externalField) {
        return;
      }
      const duplicatePair = rows.some(
        (row) => row.sfField === sfField && row.externalField === externalField
      );
      if (duplicatePair) {
        return;
      }
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
        syncDirection:
          suggestion.syncDirection || this.getDefaultSyncDirection(),
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
          connectorLabel: "QuickBooks Online",
          salesforceObject: this.selectedSFObject,
          externalObject: this.selectedQBObject,
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

  loadChildFields() {
    this.childSfFieldOptions = [];
    this.childQbFieldOptions = [];
    this.childMappingRows = [];

    Promise.all([
      getObjectFields({ objectName: this.childSfObject }),
      getQuickBooksFields({
        sfObject: this.childSfObject,
        qbObject: this.childQbObject
      }),
      getExistingMappings({
        integration: this.selectedIntegration,
        sfObject: this.childSfObject,
        qbObject: this.childQbObject
      })
    ])
      .then(([sfFields, qbFields, savedMappings]) => {
        this.childSfFieldOptions = (sfFields || []).map((f) => ({
          label: f.label,
          value: f.value,
          type: f.type
        }));
        this.childQbFieldOptions = (qbFields || []).map((f) => ({
          label: f.label + (f.required ? " *" : ""),
          value: f.value,
          type: f.type,
          required: f.required
        }));
        this.initializeChildRows(savedMappings || []);
      })
      .catch((error) => {
        console.error("Error loading child fields:", error);
        this.showToast(
          "Error",
          "Failed to load child fields: " +
            (error.body?.message || error.message),
          "error"
        );
      });
  }

  initializeChildRows(savedMappings = []) {
    if (!this.childQbFieldOptions || this.childQbFieldOptions.length === 0) {
      this.childMappingRows = [];
      return;
    }

    let cCounter = 1000;
    const rows = [];

    // Required QB fields – mandatory rows
    this.childQbFieldOptions.forEach((qbField) => {
      if (!qbField) return;
      if (qbField.required) {
        const existing = savedMappings.find(
          (m) => m.externalField === qbField.value
        );
        const syncDir = existing
          ? this.getAvailableDirectionValue(existing.syncDirection)
          : this.getAvailableDirectionValue();
        rows.push({
          id: cCounter++,
          sfField: existing?.sfField || "",
          qbField: qbField.value,
          isMandatory: true,
          isSFFieldDisabled: false,
          syncDirection: syncDir,
          fieldBorderClass:
            syncDir === "Two-Way"
              ? "custom-select-table sync-dir-two-way"
              : "custom-select-table sync-dir-one-way",
          sfFieldOptions: this.buildChildSfOptions(existing?.sfField || ""),
          qbFieldOptions: this.buildChildQbOptions(qbField.value),
          syncDirectionOptions: this.buildSyncDirectionOptions(syncDir)
        });
      }
    });

    // Non‑required saved mappings (additional rows)
    savedMappings.forEach((mapping) => {
      const isRequired = this.childQbFieldOptions.some(
        (f) => f.required && f.value === mapping.externalField
      );
      if (!isRequired) {
        const syncDir = this.getAvailableDirectionValue(mapping.syncDirection);
        rows.push({
          id: cCounter++,
          sfField: mapping.sfField,
          qbField: mapping.externalField,
          isMandatory: false,
          isSFFieldDisabled: false,
          syncDirection: syncDir,
          fieldBorderClass:
            syncDir === "Two-Way"
              ? "custom-select-table sync-dir-two-way"
              : "custom-select-table sync-dir-one-way",
          sfFieldOptions: this.buildChildSfOptions(mapping.sfField),
          qbFieldOptions: this.buildChildQbOptions(mapping.externalField),
          syncDirectionOptions: this.buildSyncDirectionOptions(syncDir)
        });
      }
    });

    this.childMappingRows = rows;
  }

  resetChildMappingRows() {
    let cCounter = 1000;
    const defaultDirection = this.getAvailableDirectionValue();
    const requiredQbFields = (this.childQbFieldOptions || []).filter(
      (field) => field.required
    );

    const rows = requiredQbFields.map((qbField) => ({
      id: cCounter++,
      sfField: "",
      qbField: qbField.value,
      isMandatory: true,
      isSFFieldDisabled: false,
      isQbFieldBlank: false,
      isSfFieldBlank: true,
      syncDirection: defaultDirection,
      fieldBorderClass:
        defaultDirection === "Two-Way"
          ? "custom-select-table sync-dir-two-way"
          : "custom-select-table sync-dir-one-way",
      sfFieldOptions: this.buildChildSfOptions(""),
      qbFieldOptions: this.buildChildQbOptions(qbField.value),
      syncDirectionOptions: this.buildSyncDirectionOptions(defaultDirection)
    }));

    if (rows.length === 0 && this.childQbFieldOptions?.length) {
      rows.push({
        id: cCounter++,
        sfField: "",
        qbField: "",
        isMandatory: false,
        isSFFieldDisabled: true,
        isQbFieldBlank: true,
        isSfFieldBlank: true,
        syncDirection: defaultDirection,
        fieldBorderClass:
          defaultDirection === "Two-Way"
            ? "custom-select-table sync-dir-two-way"
            : "custom-select-table sync-dir-one-way",
        sfFieldOptions: this.buildChildSfOptions(""),
        qbFieldOptions: this.buildChildQbOptions(""),
        syncDirectionOptions: this.buildSyncDirectionOptions(defaultDirection)
      });
    }

    this.childMappingRows = rows;
  }

  buildChildSfOptions(selectedValue) {
    if (!this.childSfFieldOptions || !Array.isArray(this.childSfFieldOptions)) {
      return [];
    }
    return this.childSfFieldOptions.map((opt) => ({
      ...opt,
      selected: opt.value === selectedValue
    }));
  }

  buildChildQbOptions(selectedValue) {
    if (!this.childQbFieldOptions || !Array.isArray(this.childQbFieldOptions)) {
      return [];
    }
    return this.childQbFieldOptions.map((opt) => ({
      ...opt,
      selected: opt.value === selectedValue
    }));
  }

  buildSyncDirectionOptions(selectedValue) {
    const allowedDirections = this.getAllowedSyncDirectionOptions();
    if (!allowedDirections || !Array.isArray(allowedDirections)) {
      return [];
    }
    return allowedDirections.map((option) => ({
      ...option,
      selected: option.value === selectedValue
    }));
  }

  handleAddChildRow() {
    const newId =
      this.childMappingRows.length > 0
        ? Math.max(...this.childMappingRows.map((r) => r.id)) + 1
        : 1000;
    const defaultDir = this.getAvailableDirectionValue();

    this.childMappingRows = [
      ...this.childMappingRows,
      {
        id: newId,
        sfField: "",
        qbField: "",
        isMandatory: false,
        isSFFieldDisabled: true,
        syncDirection: defaultDir,
        fieldBorderClass:
          defaultDir === "Two-Way"
            ? "custom-select-table sync-dir-two-way"
            : "custom-select-table sync-dir-one-way",
        sfFieldOptions: this.buildChildSfOptions(""),
        qbFieldOptions: this.buildChildQbOptions(""),
        syncDirectionOptions: this.buildSyncDirectionOptions(defaultDir)
      }
    ];
  }

  handleRemoveChildRow(event) {
    const rowId = event.currentTarget?.dataset?.rowId;
    if (!rowId) return;
    const numericRowId = Number(rowId);
    if (isNaN(numericRowId)) return;

    this.childMappingRows = this.childMappingRows.filter(
      (row) => row && row.id !== numericRowId
    );
  }

  handleChildSfFieldChange(event) {
    const rowId = event.currentTarget?.dataset?.rowId;
    if (!rowId) return;
    const numericRowId = Number(rowId);
    if (isNaN(numericRowId)) return;

    const value = event.target.value;

    this.childMappingRows = this.childMappingRows
      .map((row) => {
        if (!row || row.id !== numericRowId) return row;
        return {
          ...row,
          sfField: value,
          sfFieldOptions: this.buildChildSfOptions(value)
        };
      })
      .filter((row) => row);
  }

  handleChildQbFieldChange(event) {
    const rowId = event.currentTarget?.dataset?.rowId;
    if (!rowId) return;
    const numericRowId = Number(rowId);
    if (isNaN(numericRowId)) return;

    const value = event.target.value;

    this.childMappingRows = this.childMappingRows
      .map((row) => {
        if (!row || row.id !== numericRowId) return row;
        const isSFFieldDisabled = !value;
        return {
          ...row,
          qbField: value,
          qbFieldOptions: this.buildChildQbOptions(value),
          isSFFieldDisabled: isSFFieldDisabled
        };
      })
      .filter((row) => row);
  }

  handleChildSyncDirectionChange(event) {
    const rowId = event.currentTarget?.dataset?.rowId;
    if (!rowId) return;
    const numericRowId = Number(rowId);
    if (isNaN(numericRowId)) return;

    const value = event.target.value;

    this.childMappingRows = this.childMappingRows
      .map((row) => {
        if (!row || row.id !== numericRowId) return row;
        return {
          ...row,
          syncDirection: value,
          fieldBorderClass:
            value === "Two-Way"
              ? "custom-select-table sync-dir-two-way"
              : "custom-select-table sync-dir-one-way",
          syncDirectionOptions: this.buildSyncDirectionOptions(value)
        };
      })
      .filter((row) => row);
  }

  handleDraftChange(event) {
    this.mapDraftAsEstimate = event.target.checked;
    saveDraftOrderSetting({ value: this.mapDraftAsEstimate }).catch((error) => {
      this.showToast(
        "Error",
        "Failed to save setting: " + (error.body?.message || error.message),
        "error"
      );
      // Revert checkbox if save fails
      this.mapDraftAsEstimate = !event.target.checked;
    });
  }
}