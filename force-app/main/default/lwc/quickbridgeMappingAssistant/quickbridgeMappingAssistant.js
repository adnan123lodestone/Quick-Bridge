import { LightningElement, api, track } from "lwc";
import reviewMappings from "@salesforce/apex/QuickBridgeMappingAssistantController.reviewMappings";
import suggestMappings from "@salesforce/apex/QuickBridgeMappingAssistantController.suggestMappings";
import generateCodexPrompt from "@salesforce/apex/QuickBridgeMappingAssistantController.generateCodexPrompt";

export default class QuickbridgeMappingAssistant extends LightningElement {
  @api connectorKey;
  @api connectorLabel;
  @api salesforceObject;
  @api externalObject;
  @api syncDirection;
  @api allowApply = false;

  @track suggestions = [];
  @track missingRequiredFields = [];
  @track risks = [];
  @track isLoading = false;
  @track errorMessage = "";
  @track generatedPrompt = "";

  healthScore = 0;
  statusText = "Needs Context";
  requiredFieldsTotal = 0;
  requiredFieldsMapped = 0;
  currentMappingsValue = [];
  analysisQueued = false;

  @api
  get currentMappings() {
    return this.currentMappingsValue;
  }

  set currentMappings(value) {
    this.currentMappingsValue = Array.isArray(value) ? value : [];
    this.queueAnalysis();
  }

  connectedCallback() {
    this.queueAnalysis();
  }

  renderedCallback() {
    if (this.analysisQueued) {
      this.analysisQueued = false;
      this.refreshAnalysis();
    }
  }

  queueAnalysis() {
    this.analysisQueued = true;
  }

  get hasContext() {
    return Boolean(
      this.connectorKey && this.salesforceObject && this.externalObject
    );
  }

  get displayConnectorLabel() {
    return this.connectorLabel || this.connectorKey || "Mapping";
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasMissingFields() {
    return this.missingRequiredFields.length > 0;
  }

  get hasRisks() {
    return this.risks.length > 0;
  }

  get hasSuggestions() {
    return this.suggestions.length > 0;
  }

  get selectedSuggestions() {
    return this.suggestions.filter((suggestion) => suggestion.selected);
  }

  get disableApply() {
    return !this.allowApply || !this.hasSuggestions;
  }

  get disableApplySelected() {
    return !this.allowApply || this.selectedSuggestions.length === 0;
  }

  get statusClass() {
    const normalized = (this.statusText || "")
      .toLowerCase()
      .replace(/\s+/g, "-");
    return `status-badge ${normalized}`;
  }

  handleRefresh() {
    this.refreshAnalysis();
  }

  handleSuggest() {
    if (!this.hasContext) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    suggestMappings({
      connectorKey: this.connectorKey,
      salesforceObject: this.salesforceObject,
      externalObject: this.externalObject
    })
      .then((result) => {
        this.suggestions = this.decorateSuggestions(result || []);
      })
      .catch((error) => {
        this.errorMessage = this.errorText(error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  refreshAnalysis() {
    if (!this.hasContext) {
      this.resetAnalysis();
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    reviewMappings({
      connectorKey: this.connectorKey,
      salesforceObject: this.salesforceObject,
      externalObject: this.externalObject,
      mappingsJson: JSON.stringify(this.currentMappingsValue || [])
    })
      .then((result) => {
        this.healthScore = result?.healthScore || 0;
        this.statusText = result?.status || "Needs Context";
        this.missingRequiredFields = result?.missingRequiredFields || [];
        this.risks = result?.risks || [];
        this.suggestions = this.decorateSuggestions(result?.suggestions || []);
        const missingCount = this.missingRequiredFields.length;
        const mappedRequired = this.currentMappingsValue.filter(
          (row) => row?.isMandatory && (row.sfField || row.salesforceField)
        ).length;
        this.requiredFieldsTotal = mappedRequired + missingCount;
        this.requiredFieldsMapped = mappedRequired;
      })
      .catch((error) => {
        this.errorMessage = this.errorText(error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  decorateSuggestions(rawSuggestions) {
    return (rawSuggestions || []).map((suggestion, index) => ({
      ...suggestion,
      key: `${suggestion.salesforceField || index}-${suggestion.externalField || index}`,
      selected: false,
      disabled: suggestion.canApply === false,
      confidenceClass:
        suggestion.confidenceLabel === "High"
          ? "confidence high"
          : "confidence medium"
    }));
  }

  resetAnalysis() {
    this.healthScore = 0;
    this.statusText = "Needs Context";
    this.requiredFieldsTotal = 0;
    this.requiredFieldsMapped = 0;
    this.missingRequiredFields = [];
    this.risks = [];
    this.suggestions = [];
    this.generatedPrompt = "";
    this.errorMessage = "";
    this.isLoading = false;
  }

  handleSuggestionToggle(event) {
    const index = Number(event.currentTarget.dataset.index);
    const checked = event.currentTarget.checked;
    this.suggestions = this.suggestions.map((suggestion, suggestionIndex) => {
      return suggestionIndex === index
        ? { ...suggestion, selected: checked }
        : suggestion;
    });
  }

  handleApplySelected() {
    this.emitSuggestions(this.selectedSuggestions);
  }

  handleApplyHighConfidence() {
    const highConfidence = this.suggestions.filter(
      (suggestion) =>
        suggestion.canApply !== false &&
        (suggestion.confidenceLabel === "High" ||
          Number(suggestion.confidence) >= 80)
    );
    this.emitSuggestions(highConfidence);
  }

  emitSuggestions(suggestions) {
    if (!this.allowApply || !suggestions.length) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("applysuggestions", {
        bubbles: true,
        composed: true,
        detail: {
          connectorKey: this.connectorKey,
          salesforceObject: this.salesforceObject,
          externalObject: this.externalObject,
          suggestions
        }
      })
    );
  }

  handleGeneratePrompt() {
    if (!this.hasContext) {
      return;
    }
    this.errorMessage = "";
    generateCodexPrompt({
      connectorKey: this.connectorKey,
      salesforceObject: this.salesforceObject,
      externalObject: this.externalObject
    })
      .then((result) => {
        this.generatedPrompt = result || "";
      })
      .catch((error) => {
        this.errorMessage = this.errorText(error);
      });
  }

  errorText(error) {
    return error?.body?.message || error?.message || "Mapping analysis failed.";
  }
}
