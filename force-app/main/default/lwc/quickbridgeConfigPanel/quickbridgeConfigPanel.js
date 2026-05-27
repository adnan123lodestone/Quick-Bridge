import { LightningElement, track } from "lwc";
import verifyCredentialsAndGetGateways from "@salesforce/apex/QuickBridgeAdminControlPlaneService.verifyCredentialsAndGetGateways";
import getConnectorConfigs from "@salesforce/apex/PaymentMetadataService.getConnectorConfigs";
import saveConnectorConfig from "@salesforce/apex/PaymentMetadataService.saveConnectorConfig";
import getConfigPanelPreferences from "@salesforce/apex/PaymentMetadataService.getConfigPanelPreferences";
import updateAvailableProductsVisible from "@salesforce/apex/PaymentMetadataService.updateAvailableProductsVisible";
import checkIntegrationExpiry from "@salesforce/apex/PaymentMetadataService.checkIntegrationExpiry";
import sendProductRenewalRequest from "@salesforce/apex/PaymentMetadataService.sendProductRenewalRequest";
import getConnectorDescriptors from "@salesforce/apex/IntegrationConnectorRegistry.getConnectorDescriptors";
import revokeAdminSession from "@salesforce/apex/QuickBridgeAdminControlPlaneService.revokeAdminSession";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import QuickBridge_Logo from "@salesforce/resourceUrl/QuickBridge_Logo";
import QB_Logo from "@salesforce/resourceUrl/QB_Logo";
import FedEx_Logo from "@salesforce/resourceUrl/FedEx_Logo";
import UPS_Logo from "@salesforce/resourceUrl/UPS_Logo";
import Authorize_Net_logo from "@salesforce/resourceUrl/Authorize_Net_logo";
import recoverPin from "@salesforce/apex/QuickBridgeAdminControlPlaneService.recoverPin";
import refreshLicenses from "@salesforce/apex/QuickBridgeAdminControlPlaneService.refreshLicenses";

const LOGO_BY_CONNECTOR_KEY = {
  qbo: QB_Logo,
  quickbooks: QB_Logo,
  fedex: FedEx_Logo,
  ups: UPS_Logo,
  authorizenet: Authorize_Net_logo
};

export default class QuickbridgeConfigPanel extends LightningElement {
  @track currentScreen = "login";
  @track isLoggingIn = false;
  @track isSaving = false;
  @track isRecoveringPin = false;
  @track availableProductsVisible = true;
  @track isSavingAvailableProductsPreference = false;
  @track integrationExpiryAlert = null;
  @track isRenewalModalOpen = false;
  @track isSendingRenewalEmail = false;
  @track renewalProducts = [];

  userId = "";
  recoverUserId = "";
  adminSessionToken = "";
  adminSessionExpiresAt = null;
  @track selectedTile = "";
  quickBridgeLogo = QuickBridge_Logo;

  allTilesDefinition = [];

  @track paymentMetadataConfigs = [];
  metadataFormValues = {};

  get isLoginScreen() {
    return this.currentScreen === "login";
  }
  get isTilesScreen() {
    return this.currentScreen === "tiles";
  }
  get isConfigScreen() {
    return this.currentScreen === "config";
  }
  get isForgotPinScreen() {
    return this.currentScreen === "forgotPin";
  }
  get isDashboardScreen() {
    return this.currentScreen === "dashboard";
  }
  get isReportingScreen() {
    return this.currentScreen === "reporting";
  }
  get isLoggedIn() {
    return this.currentScreen !== "login" && this.currentScreen !== "forgotPin";
  }

  get isMappingScreen() {
    return this.currentScreen === "mapping";
  }
  isTileSelected(key) {
    return this.selectedTile === key;
  }
  get selectedConnectorKey() {
    return this.selectedTile || null;
  }
  get selectedConnectorDescriptor() {
    return (
      this.allTilesDefinition.find((t) => t.id === this.selectedTile) || null
    );
  }
  get tileIs() {
    const key = this.selectedTile;
    const result = {};
    for (const tile of this.allTilesDefinition) {
      result[tile.id] = tile.id === key;
    }
    return result;
  }
  get isSchedulerAvailable() {
    return this.selectedTileDefinition?.hasScheduler === true;
  }
  get isQboOrShopify() {
    return this.isSchedulerAvailable;
  }
  get isSchedulerScreen() {
    return this.currentScreen === "scheduler";
  }
  get selectedTileDefinition() {
    return this.getTileDefinition(this.selectedTile) || null;
  }
  get isSchedulerUnavailable() {
    return this.selectedTileDefinition?.hasScheduler !== true;
  }

  get navHomeClass() {
    return this.currentScreen === "tiles" ? "nav-button active" : "nav-button";
  }
  get navDashboardClass() {
    return this.currentScreen === "dashboard"
      ? "nav-button active"
      : "nav-button";
  }
  get navReportingClass() {
    return this.currentScreen === "reporting"
      ? "nav-button active"
      : "nav-button";
  }
  get navMappingClass() {
    return this.currentScreen === "mapping"
      ? "nav-button active"
      : "nav-button";
  }
  get navSchedulerClass() {
    return this.currentScreen === "scheduler"
      ? "nav-button active"
      : "nav-button";
  }
  get showSidebarBackButton() {
    return this.currentScreen !== "tiles";
  }

  get subscribedTiles() {
    return this.allTilesDefinition.filter((tile) => {
      const config = this.getConfigForTile(tile.id);
      return this.isConfigActiveAndCurrent(tile.id, config);
    });
  }

  get availableTiles() {
    return this.allTilesDefinition.filter((tile) => {
      const config = this.getConfigForTile(tile.id);
      return !this.isConfigActiveAndCurrent(tile.id, config);
    });
  }

  get hasSelectedConfig() {
    return this.paymentMetadataConfigs.some((c) => c.isSelected === true);
  }

  get navSettingsClass() {
    return this.currentScreen === "config" ? "nav-button active" : "nav-button";
  }

  navigateToSettings() {
    if (!this.isLoggedIn) return;
    if (!this.selectedTile) {
      this.showToast(
        "No Gateway Selected",
        "Please select a gateway from Integrations first.",
        "warning"
      );
      return;
    }
    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map((c) => ({
      ...c,
      isSelected: c.provider.toLowerCase() === this.selectedTile.toLowerCase(),
      isEditing: false // start in read‑only mode
    }));

    this.currentScreen = "config";
  }

  isSubscribedTile(tileId) {
    return this.subscribedTiles.some((tile) => tile.id === tileId);
  }

  get selectedReportingProductKey() {
    const tile = this.getTileDefinition(this.selectedTile);
    return tile?.productKey || this.selectedTile || "";
  }

  get subscribedReportingProductKeys() {
    return this.subscribedTiles
      .map((tile) => tile.productKey || tile.id)
      .filter(Boolean);
  }

  get availableReportingProductKeys() {
    return this.availableTiles
      .map((tile) => tile.productKey || tile.id)
      .filter(Boolean);
  }

  navigateToScheduler() {
    if (this.isLoggedIn) {
      this.currentScreen = "scheduler";
    }
  }

  get hasSubscribedTiles() {
    return this.subscribedTiles.length > 0;
  }

  get renewalExistingProducts() {
    return this.renewalProducts.filter((product) => product.isSubscribed);
  }

  get renewalAdditionalProducts() {
    return this.renewalProducts.filter((product) => !product.isSubscribed);
  }

  get hasRenewalExistingProducts() {
    return this.renewalExistingProducts.length > 0;
  }

  get hasRenewalAdditionalProducts() {
    return this.renewalAdditionalProducts.length > 0;
  }

  get hasRenewalSelections() {
    return this.renewalProducts.some((product) => product.selected);
  }

  get renewalSubmitDisabled() {
    return this.isSendingRenewalEmail || !this.hasRenewalSelections;
  }

  get availableProductsToggleLabel() {
    return this.availableProductsVisible ? "Hide" : "Show";
  }

  get availableProductsToggleIcon() {
    return this.availableProductsVisible ? "utility:hide" : "utility:preview";
  }

  get availableProductsToggleTitle() {
    return this.availableProductsVisible
      ? "Hide Available Products"
      : "Show Available Products";
  }

  getConfigForTile(tileId) {
    const tile = this.getTileDefinition(tileId);
    const aliases = tile?.aliases || [tileId];
    return this.paymentMetadataConfigs.find((config) => {
      const provider = (config.provider || "")
        .toLowerCase()
        .replace(/\s+/g, "");
      return aliases.some(
        (alias) => provider === alias.toLowerCase().replace(/\s+/g, "")
      );
    });
  }

  getTileDefinition(tileId) {
    return this.allTilesDefinition.find((tile) => tile.id === tileId);
  }

  isConfigActiveAndCurrent(tileId, config) {
    if (!config || config.active !== true) {
      return false;
    }

    if (this.isTileSubscriptionExpired(tileId, config)) {
      return false;
    }
    if (this.isStartDateAfterEndDate(tileId, config)) {
      return false;
    }
    return true;
  }

  isTileSubscriptionExpired(tileId, config) {
    if (!config) {
      return false;
    }

    const fields = config.fields || config.formValues || {};
    const tile = this.getTileDefinition(tileId);
    const expiryFields = tile?.expiryField ? [tile.expiryField] : [];
    const expiryValue = expiryFields
      .map((field) => fields[field])
      .find((value) => value);
    if (!expiryValue) {
      return false;
    }

    const expiryDate = new Date(`${expiryValue}T23:59:59`);
    if (Number.isNaN(expiryDate.getTime())) {
      return false;
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return expiryDate < today;
  }

  isStartDateAfterEndDate(tileId, config) {
    if (!config) {
      return false;
    }

    const fields = config.fields || config.formValues || {};
    const tile = this.getTileDefinition(tileId);
    const startFields = tile?.startField ? [tile.startField] : [];
    const expiryFields = tile?.expiryField ? [tile.expiryField] : [];

    const startValue = startFields
      .map((field) => fields[field])
      .find((value) => value);
    const endValue = expiryFields
      .map((field) => fields[field])
      .find((value) => value);

    if (!startValue || !endValue) {
      return true;
    }

    const startDate = new Date(`${startValue}T00:00:00`);
    const endDate = new Date(`${endValue}T23:59:59`);

    if (
      !Number.isNaN(startDate.getTime()) &&
      !Number.isNaN(endDate.getTime())
    ) {
      return startDate > endDate;
    }

    return false;
  }

  connectedCallback() {
    this.loadConnectorTiles();
    this.restoreSessionFromStorage();
  }

  handleUserIdChange(event) {
    this.userId = event.target.value;
  }

  async loadConnectorTiles() {
    try {
      const descriptors = await getConnectorDescriptors();
      const tiles = (descriptors || [])
        .filter((connector) => connector.catalogActive !== false)
        .filter(
          (connector) =>
            connector.hasConfig ||
            connector.hasReporting ||
            connector.hasMapping
        )
        .map((connector) => ({
          id: connector.connectorKey,
          label: connector.label,
          logoUrl: this.resolveTileLogoUrl(
            connector.connectorKey,
            connector.logoUrl
          ),
          productKey: connector.productKey,
          aliases: this.buildTileAliases(connector),
          activeField: connector.activeField,
          expiryField: connector.expiryField,
          startField: this.deriveStartField(connector.expiryField),
          hasConfig: connector.hasConfig,
          hasReporting: connector.hasReporting,
          hasMapping: connector.hasMapping,
          hasScheduler: connector.hasScheduler
        }))
        .filter((tile) => tile.id && tile.label);
      if (tiles.length) {
        this.allTilesDefinition = tiles;
      }
    } catch (error) {
      console.error(error);
    }
  }

  resolveTileLogoUrl(connectorKey, descriptorLogoUrl) {
    return (
      LOGO_BY_CONNECTOR_KEY[connectorKey] ||
      descriptorLogoUrl ||
      QuickBridge_Logo
    );
  }

  buildTileAliases(connector) {
    const values = [connector.connectorKey, connector.productKey];
    if (connector.aliases) {
      connector.aliases
        .split(",")
        .forEach((aliasValue) => values.push(aliasValue.trim()));
    }
    return [...new Set(values.filter(Boolean))];
  }

  deriveStartField(expiryField) {
    if (!expiryField) return null;
    if (expiryField.includes("End_Date__c"))
      return expiryField.replace("End_Date__c", "Start_Date__c");
    if (expiryField.includes("EndDate__c"))
      return expiryField.replace("EndDate__c", "StartDate__c");
    return null;
  }

  handleRecoverUserIdChange(event) {
    this.recoverUserId = event.target.value;
  }

  handlePinInput(event) {
    const input = event.target;
    const index = parseInt(input.dataset.index, 10);

    let value = input.value.replace(/[^0-9]/g, "");
    if (value.length > 1) {
      value = value.slice(0, 1);
    }
    input.value = value;

    if (value.length === 1 && index < 3) {
      const nextInput = this.template.querySelector(
        `.pin-input[data-index="${index + 1}"]`
      );
      if (nextInput) {
        nextInput.removeAttribute("disabled");
        nextInput.focus();
      }
    }
  }

  handlePinKeyDown(event) {
    const input = event.target;
    const index = parseInt(input.dataset.index, 10);

    if (event.key === "Backspace") {
      if (!input.value && index > 0) {
        const prevInput = this.template.querySelector(
          `.pin-input[data-index="${index - 1}"]`
        );
        if (prevInput) {
          prevInput.focus();
          prevInput.value = "";
          input.setAttribute("disabled", "true");
        }
      }
    }
  }

  getEnteredPin() {
    let pin = "";
    const boxes = this.template.querySelectorAll(".pin-box");
    boxes.forEach((box) => {
      pin += box.value;
    });
    return pin;
  }

  async handleLogin(event) {
    if (event) event.preventDefault();

    let pinCode = "";
    const pinInputs = this.template.querySelectorAll(".pin-input");
    pinInputs.forEach((input) => {
      pinCode += input.value;
    });

    if (!this.userId || pinCode.length < 4) {
      this.showToast(
        "Error",
        "Please enter your User ID and complete 4-Digit PIN.",
        "error"
      );
      return;
    }

    this.isLoggingIn = true;
    try {
      const responseStr = await verifyCredentialsAndGetGateways({
        username: this.userId,
        password: pinCode
      });
      const response = JSON.parse(responseStr);

      if (response.status === "Success") {
        this.adminSessionToken = response.sessionToken || "";
        this.adminSessionExpiresAt = response.sessionExpiresAt || null;
        this.persistSessionToStorage();
        this.selectedTile = "";
        this.currentGatewayProperName = "";
        this.currentScreen = "reporting";
        this.loadMetadataConfigs();
        this.loadConfigPanelPreferences();
      } else {
        this.showToast("Login Failed", response.message, "error");
      }
    } catch {
      this.showToast("Error", "Could not connect to Server.", "error");
    } finally {
      this.isLoggingIn = false;
    }
  }

  handleLogout() {
    const sessionToken = this.getSessionToken();
    if (sessionToken) {
      revokeAdminSession({ sessionToken }).catch(() => {});
    }
    this.userId = "";
    this.clearSessionStorage();
    this.currentScreen = "login";
  }

  getSessionToken() {
    const token = this.adminSessionToken;
    if (token) {
      const expiresAt = this.adminSessionExpiresAt
        ? new Date(this.adminSessionExpiresAt)
        : null;
      if (expiresAt && expiresAt.getTime() <= Date.now()) {
        this.clearSessionStorage();
        return null;
      }
      return token;
    }
    return null;
  }

  handleSessionError(error) {
    const message =
      typeof error === "string"
        ? error
        : error?.body?.message || error?.message || "";
    if (!message || !message.toLowerCase().includes("session")) {
      return false;
    }
    this.userId = "";
    this.clearSessionStorage();
    this.selectedTile = "";
    this.currentGatewayProperName = "";
    this.currentScreen = "login";
    this.showToast(
      "Session Expired",
      "Please log in again to continue.",
      "warning"
    );
    return true;
  }

  // --- SIDEBAR NAVIGATION METHODS ---
  navigateToHome() {
    if (this.isLoggedIn) {
      this.selectedTile = "";
      this.currentGatewayProperName = "";
      this.integrationExpiryAlert = null;
      this.currentScreen = "tiles";
    }
  }

  navigateToHomeResetContext() {
    if (this.isLoggedIn) {
      this.selectedTile = "";
      this.currentGatewayProperName = "";
      this.integrationExpiryAlert = null;
      this.currentScreen = "tiles";
    }
  }

  navigateToDashboard() {
    if (this.isLoggedIn) {
      this.currentScreen = "dashboard";
    }
  }

  navigateToReporting() {
    if (this.isLoggedIn) {
      this.currentScreen = "reporting";
    }
  }

  handleSidebarBack() {
    if (
      this.currentScreen === "config" ||
      this.currentScreen === "dashboard" ||
      this.currentScreen === "reporting" ||
      this.currentScreen === "mapping" ||
      this.currentScreen === "scheduler"
    ) {
      this.selectedTile = "";
      this.currentGatewayProperName = "";
      this.currentScreen = "tiles";
    }
  }

  handleTileClick(event) {
    const clickedTileId = event.currentTarget.dataset.id;
    this.selectedTile = clickedTileId;
    this.integrationExpiryAlert = null;
    const isActiveProduct = this.isSubscribedTile(clickedTileId);

    const tileDef = this.allTilesDefinition.find(
      (tile) => tile.id === clickedTileId
    );
    if (tileDef) {
      this.currentGatewayProperName = tileDef.label;
    }

    this.handleIntegrationExpiryAlert(clickedTileId);

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map((c) => ({
      ...c,
      isSelected: c.provider.toLowerCase() === this.selectedTile.toLowerCase(),
      isEditing: false
    }));
    this.currentScreen = isActiveProduct ? "reporting" : "config";
  }

  handleBackToTiles() {
    this.navigateToHomeResetContext();
  }

  async loadMetadataConfigs() {
    try {
      const configs = await getConnectorConfigs();

      this.paymentMetadataConfigs = (configs || []).map((config) => {
        const formValues = { ...config.fields };
        const registryLabels = config.fieldLabels || {};

        // Build editable fields data
        const editableFieldsData = (config.editableFields || []).map(
          (fieldName) => {
            const isCheckbox =
              fieldName.includes("Active") || fieldName.includes("Sandbox");
            const isReadOnlyDate = fieldName.includes("Date");
            const isTrue =
              formValues[fieldName] === "true" ||
              formValues[fieldName] === true;

            const properLabel =
              registryLabels[fieldName] ||
              fieldName.replace("__c", "").replace(/_/g, " ");

            return {
              name: fieldName,
              label: properLabel,
              isCheckbox: isCheckbox,
              isReadOnly: isReadOnlyDate,
              currentValue: isCheckbox ? isTrue : formValues[fieldName],
              displayValue: isCheckbox ? "" : formValues[fieldName] || "",
              isTrue: isTrue,
              badgeClass: isCheckbox
                ? isTrue
                  ? "badge-success"
                  : "badge-inactive"
                : ""
            };
          }
        );

        // --- Override Active Checkbox ---
        const activeField = editableFieldsData.find(
          (f) => f.isCheckbox && f.name.includes("Active")
        );
        if (activeField) {
          const tileDefinition = this.getTileDefinition(config.provider);
          const endDateField = tileDefinition?.expiryField;
          const endDateStr = formValues[endDateField];
          let isActive = false;
          if (endDateStr) {
            const endDate = new Date(endDateStr + "T23:59:59");
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            isActive = endDate >= today;
          }
          activeField.currentValue = isActive;
          activeField.isTrue = isActive;
          activeField.isReadOnly = true; // Disable in edit mode
        }
        return {
          ...config,
          isSelected: false,
          isEditing: false,
          formValues: formValues,
          editableFieldsData: editableFieldsData
        };
      });
    } catch (error) {
      console.error(error);
    }
  }

  async loadConfigPanelPreferences() {
    try {
      const preferences = await getConfigPanelPreferences();
      this.availableProductsVisible =
        preferences?.availableProductsVisible !== false;
    } catch (error) {
      console.error(error);
    }
  }

  async handleAvailableProductsToggle() {
    const nextValue = !this.availableProductsVisible;
    const previousValue = this.availableProductsVisible;
    this.availableProductsVisible = nextValue;
    this.isSavingAvailableProductsPreference = true;

    try {
      const result = await updateAvailableProductsVisible({
        visible: nextValue,
        sessionToken: this.getSessionToken()
      });
      if (!result || result.success !== true) {
        throw new Error(
          result?.message || "Could not save Available Products preference."
        );
      }
      this.showToast(
        "Preference Saved",
        nextValue
          ? "Available Products will be shown."
          : "Available Products will be hidden.",
        "success"
      );
    } catch (error) {
      if (this.handleSessionError(error)) return;
      this.availableProductsVisible = previousValue;
      this.showToast(
        "Error",
        error.body?.message ||
          error.message ||
          "Could not save Available Products preference.",
        "error"
      );
    } finally {
      this.isSavingAvailableProductsPreference = false;
    }
  }

  openRenewalRequestModal() {
    this.renewalProducts = this.allTilesDefinition.map((tile) => {
      const isSubscribed = this.isSubscribedTile(tile.id);
      return {
        ...tile,
        selected: false,
        isSubscribed,
        actionLabel: isSubscribed
          ? "Renew existing subscription"
          : "Add new subscription",
        statusLabel: isSubscribed ? "Subscribed" : "Not subscribed"
      };
    });
    this.isRenewalModalOpen = true;
  }

  closeRenewalRequestModal() {
    if (this.isSendingRenewalEmail) {
      return;
    }

    this.isRenewalModalOpen = false;
    this.renewalProducts = [];
  }

  handleRenewalProductToggle(event) {
    const productId = event.currentTarget.dataset.id;
    const selected = event.target.checked;
    this.renewalProducts = this.renewalProducts.map((product) => {
      return product.id === productId ? { ...product, selected } : product;
    });
  }

  async handleSendRenewalRequest() {
    const selectedProducts = this.renewalProducts.filter(
      (product) => product.selected
    );
    const renewalProductKeys = selectedProducts
      .filter((product) => product.isSubscribed)
      .map((product) => product.id);
    const additionalSubscriptionProductKeys = selectedProducts
      .filter((product) => !product.isSubscribed)
      .map((product) => product.id);

    if (
      !renewalProductKeys.length &&
      !additionalSubscriptionProductKeys.length
    ) {
      this.showToast(
        "Select Products",
        "Select at least one product to include in the request.",
        "warning"
      );
      return;
    }

    this.isSendingRenewalEmail = true;
    try {
      const result = await sendProductRenewalRequest({
        renewalProductKeys,
        additionalSubscriptionProductKeys,
        sessionToken: this.getSessionToken()
      });

      if (!result || result.success !== true) {
        throw new Error(
          result?.message || "Could not send the renewal request."
        );
      }

      this.showToast("Request Sent", result.message, "success");
      this.isRenewalModalOpen = false;
      this.renewalProducts = [];
    } catch (error) {
      if (this.handleSessionError(error)) return;
      this.showToast(
        "Request Failed",
        error.body?.message ||
          error.message ||
          "Could not send the renewal request.",
        "error"
      );
    } finally {
      this.isSendingRenewalEmail = false;
    }
  }

  async handleIntegrationExpiryAlert(provider) {
    try {
      const alert = await checkIntegrationExpiry({ provider });
      if (!alert || alert.shouldAlert !== true) {
        return;
      }

      this.integrationExpiryAlert = {
        ...alert,
        bannerClass: `renewal-alert renewal-alert-${alert.variant || "warning"}`
      };
      this.showToast(alert.title, alert.message, alert.variant || "warning");
    } catch (error) {
      this.integrationExpiryAlert = {
        title: "Expiry Check Failed",
        message:
          error.body?.message ||
          error.message ||
          "Could not check renewal status.",
        bannerClass: "renewal-alert renewal-alert-error"
      };
    }
  }

  toggleEditMode(event) {
    const provider = event.currentTarget.dataset.provider;
    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map((c) => {
      if (c.provider === provider) c.isEditing = !c.isEditing;
      return c;
    });
  }

  handleFieldChange(event) {
    const { field, provider } = event.target.dataset;
    const isCheckbox = event.target.type === "checkbox";
    const val = isCheckbox ? event.target.checked : event.target.value;

    if (!this.metadataFormValues[provider])
      this.metadataFormValues[provider] = {};
    this.metadataFormValues[provider][field] = val;

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map((c) => {
      if (c.provider === provider) {
        c.editableFieldsData.forEach((f) => {
          if (f.name === field) f.currentValue = val;
        });
      }
      return c;
    });
  }

  async handleSaveMetadata(event) {
    const provider = event.currentTarget.dataset.provider;
    this.isSaving = true;
    try {
      let fieldValues = this.metadataFormValues[provider] || {};
      Object.keys(fieldValues).forEach((key) => {
        if (key.includes("Active")) {
          delete fieldValues[key];
        }
      });

      const result = await saveConnectorConfig({
        connectorKey: provider,
        fieldValuesJson: JSON.stringify(fieldValues),
        sessionToken: this.getSessionToken()
      });

      if (result.success) {
        this.showToast(
          "Success",
          "Configuration saved successfully! (Deployment in background)",
          "success"
        );

        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map((c) => {
          if (c.provider === provider) {
            c.isEditing = false;
            c.isSelected = true;

            const activeFieldName = Object.keys(fieldValues).find((k) =>
              k.includes("Active")
            );
            if (activeFieldName) {
              c.active =
                fieldValues[activeFieldName] === true ||
                fieldValues[activeFieldName] === "true";
            }

            c.editableFieldsData.forEach((f) => {
              if (fieldValues[f.name] !== undefined) {
                const val = fieldValues[f.name];
                f.currentValue = val;
                f.displayValue = f.isCheckbox ? "" : val || "";
                f.isTrue = val === true || val === "true";
              }
            });
          }
          return c;
        });

        this.paymentMetadataConfigs = [...this.paymentMetadataConfigs];
      } else {
        if (this.handleSessionError(result.message)) return;
        this.showToast("Error", result.message, "error");
      }
    } catch (error) {
      if (this.handleSessionError(error)) return;
      console.error("Apex Error:", error);
      const errorMessage =
        error.body?.message || error.message || "Failed to save configuration.";
      this.showToast("Error", errorMessage, "error");
    } finally {
      this.isSaving = false;
    }
  }

  async handleMetadataDelete(event) {
    const provider = event.currentTarget.dataset.provider;

    const confirmed = await LightningConfirm.open({
      label: "Delete Configuration",
      message: `Are you sure you want to delete the configuration for ${provider}?`,
      theme: "warning"
    });

    if (!confirmed) {
      return;
    }

    this.isSaving = true;
    try {
      const config = this.paymentMetadataConfigs.find(
        (c) => c.provider === provider
      );
      const fieldValues = {};

      if (config && config.editableFieldsData) {
        config.editableFieldsData.forEach((field) => {
          fieldValues[field.name] = field.isCheckbox ? false : null;
        });
      }

      const result = await saveConnectorConfig({
        connectorKey: provider,
        fieldValuesJson: JSON.stringify(fieldValues),
        sessionToken: this.getSessionToken()
      });

      if (result.success) {
        this.showToast(
          "Deleted",
          `${provider} configuration deleted successfully!`,
          "success"
        );

        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map((c) => {
          if (c.provider === provider) {
            c.active = false;
            c.isEditing = false;
            c.editableFieldsData.forEach((f) => {
              f.currentValue = f.isCheckbox ? false : "";
              f.displayValue = f.isCheckbox ? "No" : "";
              if (f.isCheckbox) f.badgeClass = "badge-inactive";
            });
          }
          return c;
        });

        this.paymentMetadataConfigs = [...this.paymentMetadataConfigs];
        this.currentScreen = "tiles";
      } else {
        if (this.handleSessionError(result.message)) return;
        this.showToast("Delete Failed", result.message, "error");
      }
    } catch (error) {
      if (this.handleSessionError(error)) return;
      this.showToast("Error", "Failed to delete configuration.", "error");
    } finally {
      this.isSaving = false;
    }
  }

  goToForgotPinScreen() {
    this.recoverUserId = this.userId;
    this.currentScreen = "forgotPin";
  }

  handleBackToLogin() {
    this.currentScreen = "login";
  }

  async submitPinRecovery() {
    if (!this.recoverUserId) {
      this.showToast(
        "User ID Required",
        "Please enter your User ID to reset your PIN.",
        "warning"
      );
      return;
    }

    this.isRecoveringPin = true;
    try {
      const responseStr = await recoverPin({ username: this.recoverUserId });
      const response = JSON.parse(responseStr);

      if (response.status === "Success") {
        this.showToast(
          "Check Your Email",
          "If your User ID exists in our system, we have sent a PIN recovery email.",
          "success"
        );
        this.currentScreen = "login";
      } else {
        this.showToast("Notice", response.message, "error");
      }
    } catch {
      this.showToast(
        "Error",
        "Could not connect to server for PIN recovery.",
        "error"
      );
    } finally {
      this.isRecoveringPin = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  navigateToMapping() {
    if (this.isLoggedIn) {
      this.currentScreen = "mapping";
    }
  }

  restoreSessionFromStorage() {
    this.clearSessionStorage();
    this.currentScreen = "login";
  }

  persistSessionToStorage() {
    // Admin session tokens are intentionally memory-only.
  }

  readSessionFromStorage() {
    return null;
  }

  clearSessionStorage() {
    this.adminSessionToken = "";
    this.adminSessionExpiresAt = null;
  }

  handleCheckLicenses() {
    const sessionToken = this.getSessionToken();
    if (!sessionToken) {
      this.showToast("Session Expired", "Please log in again.", "error");
      return;
    }

    refreshLicenses({ sessionToken })
      .then((result) => {
        if (result.startsWith("Success")) {
          this.showToast(
            "Licenses Refreshed",
            "Active licenses and dates have been updated.",
            "success"
          );
          // Refresh the current view
          this.loadMetadataConfigs();
          this.loadConfigPanelPreferences();
          // Force re-render of tiles
          this.paymentMetadataConfigs = [...this.paymentMetadataConfigs];
        } else {
          this.showToast("Refresh Failed", result, "error");
        }
      })
      .catch((error) => {
        this.handleSessionError(error);
        this.showToast(
          "Error",
          error.body?.message || "Could not refresh licenses.",
          "error"
        );
      });
  }
}
