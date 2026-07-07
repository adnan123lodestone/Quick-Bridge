import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getConnectorDescriptors from "@salesforce/apex/ConnectorRegistryService.getConnectorDescriptors";
import getObjectFields from "@salesforce/apex/FieldMappingController.getObjectFields";
import getExternalFields from "@salesforce/apex/FieldMappingController.getExternalFields";
import getExistingMappings from "@salesforce/apex/FieldMappingController.getExistingMappings";
import saveFieldMappings from "@salesforce/apex/FieldMappingController.saveFieldMappings";
import clearFieldMappingsForTargetObject from "@salesforce/apex/FieldMappingController.clearFieldMappingsForTargetObject";

export default class ConnectorFieldMappingComponent extends LightningElement {
  @api connectorKey = "";
  @api connectorLabel = "";

  @track objectMapOptions = [];
  @track selectedObjectMapKey = "";
  @track selectedSFObject = "";
  @track selectedExternalObject = "";
  @track selectedObjectMapDirection = "";
  @track sfFieldOptions = [];
  @track externalFieldOptions = [];
  @track mappingRows = [];
  @track isLoading = true;
  @track showResetConfirm = false;

  objectMaps = [];
  rowCounter = 1;

  connectedCallback() {
    this.loadInitialData();
  }

  get externalLabel() {
    return this.connectorLabel || this.connectorKey || "External";
  }

  get hasObjectMaps() {
    return this.objectMapOptions.length > 0;
  }

  get tableTitle() {
    return `Sync Settings - ${this.externalLabel} Field Mappings`;
  }

  get requiredTitle() {
    return `Required ${this.externalLabel} Field`;
  }

  get helperText() {
    return `Choose fields from Salesforce and ${this.externalLabel} to sync between.`;
  }

  get footerText() {
    return `Map fields between Salesforce and ${this.externalLabel}, then save.`;
  }

  get duplicateErrorMessage() {
    return `Each ${this.externalLabel} field can only be mapped once.`;
  }

  get requiredErrorMessage() {
    return `Map a Salesforce field to every required ${this.externalLabel} field.`;
  }

  get selectedObjectMap() {
    return this.objectMaps.find((mapRow) => mapRow.key === this.selectedObjectMapKey);
  }

  get normalizedConnectorKey() {
    return this.normalizeConnector(this.connectorKey);
  }

  loadInitialData() {
    this.isLoading = true;
    getConnectorDescriptors()
      .then((descriptors) => {
        const descriptor = (descriptors || []).find((item) =>
          this.matchesConnector(item)
        );
        const rows = descriptor?.objectMappings || [];
        this.objectMaps = rows
          .filter((row) => row.salesforceObject && row.externalObject)
          .map((row, index) => ({
            ...row,
            key: `${row.salesforceObject}:${row.externalObject}:${index}`
          }));
        this.objectMapOptions = this.objectMaps.map((row) => ({
          label: `${row.salesforceObject} -> ${row.externalObject}`,
          value: row.key,
          selected: false
        }));

        if (!this.objectMaps.length) {
          this.isLoading = false;
          this.notifyMappingContextChange();
          return;
        }

        this.selectedObjectMapKey = this.objectMaps[0].key;
        this.applySelectedObjectMap();
        return this.loadSelectedMapping();
      })
      .catch((error) => {
        this.showToast("Error", this.reduceError(error), "error");
        this.isLoading = false;
      });
  }

  matchesConnector(descriptor) {
    const key = this.normalizedConnectorKey;
    if (!key || !descriptor) return false;
    if (this.normalizeConnector(descriptor.connectorKey) === key) return true;
    if (this.normalizeConnector(descriptor.productKey) === key) return true;
    return String(descriptor.aliases || "")
      .split(/[,\s]+/)
      .some((alias) => this.normalizeConnector(alias) === key);
  }

  applySelectedObjectMap() {
    const row = this.selectedObjectMap;
    this.selectedSFObject = row?.salesforceObject || "";
    this.selectedExternalObject = row?.externalObject || "";
    this.selectedObjectMapDirection = row?.direction || "";
    this.objectMapOptions = this.objectMapOptions.map((option) => ({
      ...option,
      selected: option.value === this.selectedObjectMapKey
    }));
  }

  loadSelectedMapping() {
    if (!this.selectedSFObject || !this.selectedExternalObject) {
      this.isLoading = false;
      this.notifyMappingContextChange();
      return Promise.resolve();
    }

    return Promise.all([
      getObjectFields({ objectName: this.selectedSFObject }),
      getExternalFields({
        integration: this.connectorKey,
        sfObject: this.selectedSFObject,
        externalObject: this.selectedExternalObject
      }),
      getExistingMappings({
        integration: this.connectorKey,
        sfObject: this.selectedSFObject,
        qbObject: this.selectedExternalObject
      })
    ])
      .then(([sfFields, externalFields, savedMappings]) => {
        this.sfFieldOptions = (sfFields || []).map((field) => ({
          ...field,
          type: this.normalizeType(field.type)
        }));
        this.externalFieldOptions = (externalFields || []).map((field) => ({
          ...field,
          type: this.normalizeType(field.type),
          required: Boolean(field.required)
        }));
        this.buildMappingRows(savedMappings || []);
        this.isLoading = false;
      })
      .catch((error) => {
        this.showToast("Error", this.reduceError(error), "error");
        this.isLoading = false;
      });
  }

  handleObjectMapChange(event) {
    this.selectedObjectMapKey = event.target.value;
    this.isLoading = true;
    this.applySelectedObjectMap();
    this.loadSelectedMapping();
  }

  buildMappingRows(savedMappings) {
    const requiredFields = this.externalFieldOptions.filter((field) => field.required);
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
        syncDirection: this.getAvailableDirectionValue(existingMapping?.syncDirection),
        isMandatory: true
      });
    });

    savedMappings.forEach((mapping) => {
      const isRequired = requiredFields.some(
        (field) => field.value === mapping.externalField
      );
      const isValidForObject = this.externalFieldOptions.some(
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

  updateRowDropdowns() {
    const allowedDirections = this.getAllowedSyncDirectionOptions();
    this.mappingRows = this.mappingRows.map((row) => {
      const externalField = this.externalFieldOptions.find(
        (option) => option.value === row.externalField
      );
      const externalType = externalField ? externalField.type : null;
      const availableSfOptions = externalType
        ? this.sfFieldOptions.filter((option) =>
            this.isTypeMatch(option.type, externalType)
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
        isSFFieldDisabled: !row.isMandatory && !row.externalField,
        isExternalFieldBlank: !row.externalField,
        isSfFieldBlank: !row.sfField,
        fieldBorderClass:
          selectedDirection === "Two-Way"
            ? "custom-select-table sync-dir-two-way"
            : "custom-select-table sync-dir-one-way",
        externalFieldOptions: this.externalFieldOptions.map((option) => ({
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
    this.mappingRows = this.mappingRows.map((row) =>
      row.id === rowId ? { ...row, sfField: value } : row
    );
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleExternalFieldChange(event) {
    const rowId = Number(event.currentTarget.dataset.rowId);
    const value = event.target.value;
    this.mappingRows = this.mappingRows.map((row) => {
      if (row.id !== rowId) return row;
      const externalField = this.externalFieldOptions.find(
        (option) => option.value === value
      );
      const sfField = this.sfFieldOptions.find(
        (option) => option.value === row.sfField
      );
      const keepSfField =
        externalField &&
        sfField &&
        this.isTypeMatch(sfField.type, externalField.type);
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
    this.mappingRows = this.mappingRows.map((row) =>
      row.id === rowId ? { ...row, syncDirection: value } : row
    );
    this.updateRowDropdowns();
    this.notifyMappingContextChange();
  }

  handleSave() {
    const duplicateExternalFields = this.getDuplicateExternalFields();
    if (duplicateExternalFields.length > 0) {
      this.showToast("Validation Error", this.duplicateErrorMessage, "error");
      return;
    }

    const missingRequiredRow = this.mappingRows.find(
      (row) => row.isMandatory && (!row.externalField || !row.sfField)
    );
    if (missingRequiredRow) {
      this.showToast("Validation Error", this.requiredErrorMessage, "error");
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
      integration: this.connectorKey,
      sfObject: this.selectedSFObject,
      qbObject: this.selectedExternalObject,
      mappingsJson: JSON.stringify(rowsToSave)
    })
      .then((result) => {
        this.isLoading = false;
        this.showToast("Success", result, "success");
        this.notifyMappingContextChange();
      })
      .catch((error) => {
        this.isLoading = false;
        this.showToast("Error", this.reduceError(error), "error");
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
    clearFieldMappingsForTargetObject({
      integration: this.connectorKey,
      sfObject: this.selectedSFObject,
      externalObject: this.selectedExternalObject
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
        this.showToast("Error", this.reduceError(error), "error");
        this.isLoading = false;
      });
  }

  resetMappingRows() {
    const requiredFields = this.externalFieldOptions.filter((field) => field.required);
    const defaultDirection = this.getDefaultSyncDirection();
    let counter = 1;
    const rows = requiredFields.map((field) => ({
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
          (row) => row.sfField === sfField && row.externalField === externalField
        )
      ) {
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
        syncDirection: this.getAvailableDirectionValue(suggestion.syncDirection),
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
          connectorKey: this.connectorKey,
          connectorLabel: this.externalLabel,
          salesforceObject: this.selectedSFObject,
          externalObject: this.selectedExternalObject,
          syncDirection: null,
          allowApply: Boolean(this.selectedSFObject && this.selectedExternalObject),
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

  getAllowedSyncDirectionOptions() {
    const connector = this.normalizedConnectorKey;
    const direction = String(this.selectedObjectMapDirection || "").toLowerCase();
    let options;
    if (connector === "meta") {
      options = [
        { label: "Meta to SF", value: "Meta to SF" },
        { label: "SF to Meta", value: "SF to Meta" },
        { label: "Two-Way", value: "Two-Way" }
      ];
    } else {
      options = [
        { label: "NetSuite to SF", value: "NetSuite to SF" },
        { label: "SF to NetSuite", value: "SF to NetSuite" },
        { label: "Two-Way", value: "Two-Way" }
      ];
    }

    if (direction.includes("bidirectional") || direction.includes("two")) {
      return options;
    }
    if (direction.includes("out")) {
      return options.filter((option) => option.value.startsWith("SF to"));
    }
    if (direction.includes("in")) {
      return options.filter((option) => option.value.endsWith("to SF"));
    }
    return options;
  }

  getDefaultSyncDirection() {
    const options = this.getAllowedSyncDirectionOptions();
    const twoWay = options.find((option) => option.value === "Two-Way");
    return (twoWay || options[0] || { value: "Two-Way" }).value;
  }

  getAvailableDirectionValue(direction, allowedDirections = null) {
    const options = allowedDirections || this.getAllowedSyncDirectionOptions();
    const value = direction || this.getDefaultSyncDirection();
    if (options.some((option) => option.value === value)) {
      return value;
    }
    return this.getDefaultSyncDirection();
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

  normalizeConnector(value) {
    return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "");
  }

  normalizeType(type) {
    const value = String(type || "").toUpperCase();
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
    if (["DATE", "DATETIME"].includes(value)) return "DATE";
    if (value === "BOOLEAN") return "BOOLEAN";
    return "STRING";
  }

  isTypeMatch(sfType, externalType) {
    if (!sfType || !externalType) return false;
    return this.normalizeType(sfType) === this.normalizeType(externalType);
  }

  reduceError(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "An unexpected mapping error occurred."
    );
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}