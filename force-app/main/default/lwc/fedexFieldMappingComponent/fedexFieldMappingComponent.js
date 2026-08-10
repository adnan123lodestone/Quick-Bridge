import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSalesforceObjectDiscovery from "@salesforce/apex/FieldMappingController.getSalesforceObjectDiscovery";
import getObjectFields from "@salesforce/apex/FieldMappingController.getObjectFields";
import getFedExFields from "@salesforce/apex/FieldMappingController.getFedExFields";
import getExistingFedExMappings from "@salesforce/apex/FieldMappingController.getExistingFedExMappings";
import saveFedExFieldMappings from "@salesforce/apex/FieldMappingController.saveFedExFieldMappings";
import clearFieldMappings from "@salesforce/apex/FieldMappingController.clearFieldMappings";
import {
  buildObjectOptions,
  firstAvailableObject,
  isConfiguredPair,
  registerConfiguredPair
} from "c/mappingObjectDiscovery";

const SHIPMENT_ONLY_ACTIONS = new Set(["voidShipment", "syncTrackingStatus"]);

const ACTIONS = [
  {
    value: "validateAddress",
    label: "Validate Address",
    scope: "Any object",
    note: "Uses SF fields to validate an address, shows the correction to the user, and only writes the selected validated address when the user confirms."
  },
  {
    value: "getRateQuote",
    label: "Get Rate Quote",
    scope: "Any object",
    note: "Builds a rate request from mapped fields, shows every returned option, and stores the user-selected response fields."
  },
  {
    value: "createShipment",
    label: "Create Shipment",
    scope: "Shipment-centric",
    note: "Creates or uses a shipment record, updates package, label, tracking, cost, and status fields after FedEx confirms."
  },
  {
    value: "syncTrackingStatus",
    label: "Sync Tracking Status",
    scope: "Shipment plus schedule",
    note: "Uses tracking number, updates latest shipment status, inserts deduped tracking events, and stops terminal shipments. Also captures tracking numbers and exception fields automatically."
  },
  {
    value: "createReturnLabel",
    label: "Create Return Label",
    scope: "Shipment, return, case, RMA",
    note: "Creates a separate return shipment, preserving the original shipment and storing return tracking plus label file data."
  },
  {
    value: "voidShipment",
    label: "Void Shipment",
    scope: "Shipment only",
    note: "Calls FedEx void/cancel before updating Salesforce and is blocked for delivered or terminal shipments."
  }
];

export default class FedexFieldMappingComponent extends LightningElement {
  @track selectedAction = "validateAddress";
  @track selectedDirection = "SF to FedEx";
  @track selectedSFObject = "Case";
  @track allSFObjectOptions = [];
  @track shipmentObjectApiName = "";

  get sfObjectOptions() {
    if (SHIPMENT_ONLY_ACTIONS.has(this.selectedAction)) {
      return this.shipmentObjectApiName
        ? [
            {
              label: "Shipment",
              value: this.shipmentObjectApiName,
              selected: true
            }
          ]
        : [];
    }
    return this.allSFObjectOptions;
  }
  @track sfFieldOptions = [];
  @track fedexFieldOptions = [];
  @track mappingRows = [];
  @track rowCounter = 1;
  @track isLoading = true;
  @track showResetConfirm = false;

  get directionOptions() {
    return [
      {
        label: "SF to FedEx",
        value: "SF to FedEx",
        selected: this.selectedDirection === "SF to FedEx"
      },
      {
        label: "FedEx to SF",
        value: "FedEx to SF",
        selected: this.selectedDirection === "FedEx to SF"
      }
    ];
  }

  get actionOptions() {
    return ACTIONS.map((action) => ({
      ...action,
      selected: action.value === this.selectedAction,
      className:
        action.value === this.selectedAction
          ? "action-tile selected"
          : "action-tile"
    }));
  }

  get selectedActionConfig() {
    return (
      ACTIONS.find((action) => action.value === this.selectedAction) ||
      ACTIONS[0]
    );
  }

  get selectedActionLabel() {
    return this.selectedActionConfig.label;
  }

  get selectedActionScope() {
    return this.selectedActionConfig.scope;
  }

  get selectedActionNote() {
    return this.selectedActionConfig.note;
  }

  get isExceptionAction() {
    return this.selectedAction === "handleDeliveryExceptions";
  }

  connectedCallback() {
    this.loadInitialData();
  }

  loadInitialData() {
    this.isLoading = true;
    this.loadSalesforceObjects()
      .then(() => this.reloadMappings())
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  loadSalesforceObjects() {
    return getSalesforceObjectDiscovery({ connectorKey: "fedex" }).then(
      (result) => {
        this.allSFObjectOptions = buildObjectOptions(
          result,
          this.selectedSFObject
        );
        this.shipmentObjectApiName =
          this.allSFObjectOptions.find(
            (option) =>
              option.available !== false &&
              option.configuredExternalObjects.includes("Shipment")
          )?.value || "";
        if (
          !this.allSFObjectOptions.some(
            (obj) =>
              obj.value === this.selectedSFObject && obj.available !== false
          ) &&
          this.allSFObjectOptions.length
        ) {
          this.selectedSFObject = firstAvailableObject(this.allSFObjectOptions);
        }
        this.allSFObjectOptions = this.allSFObjectOptions.map((option) => ({
          ...option,
          selected: option.value === this.selectedSFObject
        }));
      }
    );
  }

  reloadMappings() {
    this.isLoading = true;
    if (!this.selectedSFObject) {
      this.sfFieldOptions = [];
      this.fedexFieldOptions = [];
      this.mappingRows = [];
      this.isLoading = false;
      return Promise.resolve();
    }
    return Promise.all([
      getObjectFields({ objectName: this.selectedSFObject }),
      getFedExFields({
        actionName: this.selectedAction,
        direction: this.selectedDirection
      }),
      getExistingFedExMappings({
        actionName: this.selectedAction,
        sfObject: this.selectedSFObject
      })
    ])
      .then(([sfFields, fedexFields, savedMappings]) => {
        this.sfFieldOptions = (sfFields || []).map((field) => ({
          ...field,
          type: this.normalizeType(field.type)
        }));
        this.fedexFieldOptions = (fedexFields || []).map((field) => ({
          ...field,
          type: this.normalizeType(field.type),
          required: Boolean(field.required)
        }));
        this.buildMappingRows(savedMappings || []);
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", error.body?.message || error.message, "error");
        this.isLoading = false;
      });
  }

  buildMappingRows(savedMappings) {
    const relevantSavedMappings = savedMappings.filter((mapping) => {
      const direction = mapping.syncDirection || "SF to FedEx";
      return direction === this.selectedDirection;
    });
    const requiredFedExFields = this.fedexFieldOptions.filter(
      (field) => field.required
    );
    const rows = [];
    let counter = 1;

    requiredFedExFields.forEach((field) => {
      const existingMapping = relevantSavedMappings.find(
        (mapping) => mapping.externalField === field.value
      );
      rows.push({
        id: counter++,
        sfField: existingMapping?.sfField || "",
        externalField: field.value,
        syncDirection: this.selectedDirection,
        isMandatory: true
      });
    });

    relevantSavedMappings.forEach((mapping) => {
      const isRequired = requiredFedExFields.some(
        (field) => field.value === mapping.externalField
      );
      if (!isRequired) {
        rows.push({
          id: counter++,
          sfField: mapping.sfField,
          externalField: mapping.externalField,
          syncDirection: this.selectedDirection,
          isMandatory: false
        });
      }
    });

    if (rows.length === 0) {
      rows.push({
        id: counter++,
        sfField: "",
        externalField: "",
        syncDirection: this.selectedDirection,
        isMandatory: false
      });
    }

    this.mappingRows = rows;
    this.rowCounter = counter;
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleActionSelect(event) {
    this.selectedAction = event.currentTarget.dataset.action;
    this.selectedDirection =
      this.selectedAction === "handleDeliveryExceptions"
        ? "FedEx to SF"
        : this.selectedDirection;
    if (SHIPMENT_ONLY_ACTIONS.has(this.selectedAction)) {
      this.selectedSFObject = this.shipmentObjectApiName;
    }
    this.reloadMappings();
  }

  handleDirectionChange(event) {
    this.selectedDirection = event.target.value;
    this.reloadMappings();
  }

  handleSalesforceObjectChange(event) {
    this.selectedSFObject = event.detail?.value ?? event.target?.value ?? "";
    this.allSFObjectOptions = this.allSFObjectOptions.map((option) => ({
      ...option,
      selected: option.value === this.selectedSFObject
    }));
    this.reloadMappings();
  }

  handleAddRow() {
    this.mappingRows = [
      ...this.mappingRows,
      {
        id: this.rowCounter++,
        sfField: "",
        externalField: "",
        syncDirection: this.selectedDirection,
        isMandatory: false
      }
    ];
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleRemoveRow(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    this.mappingRows = this.mappingRows.filter((row) => row.id !== rowId);
    if (!this.mappingRows.length) {
      this.handleAddRow();
      return;
    }
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleExternalFieldChange(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    const value = event.target.value;
    this.mappingRows = this.mappingRows.map((row) => {
      if (row.id !== rowId) return row;
      const fedexField = this.fedexFieldOptions.find(
        (option) => option.value === value
      );
      const sfField = this.sfFieldOptions.find(
        (option) => option.value === row.sfField
      );
      const keepSfField =
        fedexField &&
        sfField &&
        this.isTypeMatch(sfField.type, fedexField.type);
      return {
        ...row,
        externalField: value,
        sfField: keepSfField ? row.sfField : ""
      };
    });
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

  handleSave() {
    const duplicateExternalFields = this.getDuplicateExternalFields();
    if (duplicateExternalFields.length) {
      this.showToast(
        "Validation Error",
        "Each FedEx field can only be mapped once per direction.",
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
        "Map a Salesforce field to every required FedEx field.",
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
          syncDirection: this.selectedDirection
        };
      });

    this.isLoading = true;
    saveFedExFieldMappings({
      actionName: this.selectedAction,
      sfObject: this.selectedSFObject,
      mappingsJson: JSON.stringify(rowsToSave)
    })
      .then((result) => {
        if (rowsToSave.length) {
          this.allSFObjectOptions = registerConfiguredPair(
            this.allSFObjectOptions,
            this.selectedSFObject,
            this.registrationExternalObject
          );
        }
        this.isLoading = false;
        this.showToast("Success", result, "success");
      })
      .catch((error) => {
        this.isLoading = false;
        this.showToast("Error", error.body?.message || error.message, "error");
      });
  }

  handleReset() {
    this.showResetConfirm = true;
  }

  handleResetCancel() {
    this.showResetConfirm = false;
  }

  handleResetConfirm() {
    this.showResetConfirm = false;
    this.isLoading = true;
    clearFieldMappings({
      integration: "fedex",
      sfObject: this.selectedSFObject
    })
      .then(() => {
        this.showToast(
          "Success",
          "Mappings cleared. Changes will be fully reflected after the metadata deployment completes.",
          "success"
        );
        this.mappingRows = [];
        this.rowCounter = 1;
        this.isLoading = false;
      })
      .catch((error) => {
        this.isLoading = false;
        this.showToast("Error", error.body?.message || error.message, "error");
      });
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
          existingExternal.syncDirection = this.selectedDirection;
          changed = true;
        }
        return;
      }

      rows.push({
        id: this.rowCounter++,
        sfField,
        externalField,
        syncDirection: this.selectedDirection,
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
          connectorKey: "fedex",
          connectorLabel: "FedEx",
          salesforceObject: this.selectedSFObject,
          externalObject: this.selectedAction,
          syncDirection: this.selectedDirection,
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

  updateRowDropdowns() {
    this.mappingRows = this.mappingRows.map((row) => {
      const fedexField = this.fedexFieldOptions.find(
        (option) => option.value === row.externalField
      );
      const fedexType = fedexField ? fedexField.type : null;
      const availableSfOptions = fedexType
        ? this.sfFieldOptions.filter((option) =>
            this.isTypeMatch(option.type, fedexType)
          )
        : this.sfFieldOptions;
      const currentSfFieldValid =
        row.sfField &&
        availableSfOptions.some((option) => option.value === row.sfField);

      return {
        ...row,
        sfField: currentSfFieldValid ? row.sfField : "",
        isSFFieldDisabled: !row.isMandatory && !row.externalField,
        externalFieldOptions: this.fedexFieldOptions.map((option) => ({
          ...option,
          selected: option.value === row.externalField
        })),
        sfFieldOptions: availableSfOptions.map((option) => ({
          ...option,
          selected: option.value === row.sfField
        }))
      };
    });
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

  get isMappingBlocked() {
    return !this.selectedSFObject;
  }

  get showMappingOnlyWarning() {
    if (
      SHIPMENT_ONLY_ACTIONS.has(this.selectedAction) &&
      !this.shipmentObjectApiName
    ) {
      return true;
    }
    if (!this.selectedSFObject) return false;
    return !isConfiguredPair(
      this.allSFObjectOptions,
      this.selectedSFObject,
      this.registrationExternalObject
    );
  }

  get mappingOnlyWarning() {
    if (
      SHIPMENT_ONLY_ACTIONS.has(this.selectedAction) &&
      !this.shipmentObjectApiName
    ) {
      return "The configured Salesforce shipment object is unavailable. This shipment-only action cannot be configured.";
    }
    return "This pair is not registered yet. Saving valid field mappings will register it. Automated FedEx processing remains limited to supported runtime objects.";
  }

  get registrationExternalObject() {
    return SHIPMENT_ONLY_ACTIONS.has(this.selectedAction)
      ? "Shipment"
      : "Package";
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

  isTypeMatch(sfType, fedexType) {
    if (!sfType || !fedexType) return true;
    return this.normalizeType(sfType) === this.normalizeType(fedexType);
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}