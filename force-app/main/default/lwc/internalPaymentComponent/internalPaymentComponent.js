import { LightningElement, api } from "lwc";
import getAuthorizeNetClientConfig from "@salesforce/apex/AuthorizeNetPaymentService.getClientConfig";
import processAuthorizeNetPayment from "@salesforce/apex/AuthorizeNetPaymentService.processOpaquePayment";
import getStripeClientConfig from "@salesforce/apex/StripePaymentService.getClientConfig";
import processStripePayment from "@salesforce/apex/StripePaymentService.processPayment";
import getPayPalClientConfig from "@salesforce/apex/PayPalPaymentService.getClientConfig";
import createPayPalOrder from "@salesforce/apex/PayPalPaymentService.createOrder";
import capturePayPalOrder from "@salesforce/apex/PayPalPaymentService.captureOrder";
import CardPayment_lables from "@salesforce/label/c.CardPayment_lables";
import getActiveGatewaysForCheckout from "@salesforce/apex/PaymentGatewayService.getActiveGatewaysForCheckout";

let acceptJsPromise;
let stripeJsPromise;
let paypalJsPromise;

const FORM_CACHE_KEY = 'QuickBridge_Payment_Form_Data';

export default class PaymentComponent extends LightningElement {
  selectedProvider = null; 
  @api amount = 1;
  @api orderId = "";
  @api usePlatformSession = false;
  errorDetails = {};
  isStripeInitializing = false;
  showErrorModal = false;
  showSuccessModal = false;
  successDetails = {};
  stripeDebugMessages = [];
  stripeLastStep = "Idle";
  
  paymentForm = {
    cardName: "",
    cardNumber: "",
    securityCode: "",
    cardMonth: "",
    cardYear: "",
    cardAddressOne: "",
    cardCity: "",
    cardState: "",
    cardZipCode: "",
    cardCountry: "",
  };
  
  authorizeNetConfig;
  authorizeNetReadyPromise;
  authorizeNetLibraryUrl;
  stripeCardComplete = false;
  stripeCardElement;
  stripeCardError = "";
  stripeCardMounted = false;
  stripeConfig;
  stripeInstance;
  stripeJsUrl;
  stripeReadyPromise;
  stripePreloadQueued = false;
  paypalConfig;
  paypalJsUrl;
  paypalReadyPromise;
  paypalButtonsMounted = false;
  paypalButtonsInstance;
  isPaypalInitializing = false;
  isSubmitting = false;

  CardPayment_lables = Object.fromEntries(
    CardPayment_lables.split("|").map((v, i) => [`index${i}`, v])
  );
  monthOptions = [];
  errorReturnObj;
  yearOptions = [];

  showCancelWarningModal = false;

  connectedCallback() {
    this.monthOptions = Array.from({ length: 12 }, (_, index) => {
      const value = String(index + 1);
      return { label: value, value };
    });

    const currentYear = new Date().getFullYear();
    this.yearOptions = Array.from({ length: 21 }, (_, index) => {
      const value = String(currentYear + index);
      return { label: value, value };
    });

    const cachedData = sessionStorage.getItem(FORM_CACHE_KEY);
    if (cachedData) {
      try {
        const parsedData = JSON.parse(cachedData);
        this.paymentForm = { ...this.paymentForm, ...parsedData };
      } catch (e) {
        console.error('Error reading cached payment data');
      }
    }

    this.initializeProviderConfigs();
  }

  renderedCallback() {
    if (this.selectedProvider === "stripe" && this.stripeInstance && !this.stripeCardMounted && !this.isStripeInitializing) {
      this.mountStripeCardElement();
    }
    if (this.selectedProvider === "paypal" && this.canRenderPayPalButtons && !this.paypalButtonsMounted && !this.isPaypalInitializing) {
      this.mountPayPalButtons();
    }
  }

  disconnectedCallback() {
    this.unmountStripeCardElement();
    this.unmountPayPalButtons();
  }

  stateValues = [
    { label: "AK", value: "AK" }, { label: "AL", value: "AL" }, { label: "AR", value: "AR" },
    { label: "CA", value: "CA" }, { label: "FL", value: "FL" }, { label: "NY", value: "NY" },
    { label: "TX", value: "TX" }, { label: "Outside US/Canada", value: "Outside US/Canada" },
  ];

  get isAuthorizeNetSelected() { return this.selectedProvider === "authorizenet"; }
  get isStripeSelected() { return this.selectedProvider === "stripe"; }
  get isPaypalSelected() { return this.selectedProvider === "paypal"; }
  get hasAvailableProviders() { return this.availableProviderCount > 0; }
  get showUnavailableState() { return !this.hasAvailableProviders; }

  get availableProviderCount() {
    let count = 0;
    if (this.isAuthorizeNetActive) count += 1;
    if (this.isStripeActive) count += 1;
    if (this.isPayPalActive) count += 1;
    return count;
  }

  get authorizeNetTileClass() { return this.getProviderTileClass("authorizenet"); }
  get stripeTileClass() { return this.getProviderTileClass("stripe"); }
  get paypalTileClass() { return this.getProviderTileClass("paypal"); }

  get isAuthorizeNetActive() { return this.authorizeNetConfig?.active === true; }
  get isStripeActive() { return this.stripeConfig?.active === true; }
  get isPayPalActive() { return this.paypalConfig?.active === true; }
  get isPayPalConfigured() { return this.paypalConfig?.configured === true; }
  get canRenderPayPalButtons() { return this.isPayPalActive && this.isPayPalConfigured; }

  get isAuthorizeNetDisabled() { return !this.isProviderSelectable("authorizenet"); }
  get isStripeDisabled() { return !this.isProviderSelectable("stripe"); }
  get isPaypalDisabled() { return !this.isProviderSelectable("paypal"); }

  get authorizeNetDisabledMessage() { return this.getDisabledProviderMessage(this.authorizeNetConfig); }
  get stripeDisabledMessage() { return this.getDisabledProviderMessage(this.stripeConfig); }
  get paypalDisabledMessage() { return this.getDisabledProviderMessage(this.paypalConfig); }

  get showAuthorizeNetHint() { return this.isAuthorizeNetDisabled && !!this.authorizeNetDisabledMessage; }
  get showStripeHint() { return this.isStripeDisabled && !!this.stripeDisabledMessage; }
  get showPaypalHint() { return this.isPaypalDisabled && !!this.paypalDisabledMessage; }

  get stripeTestCardNumber() { return this.paymentForm.cardNumber || ""; }

  get selectedProviderLabel() {
    if (!this.hasAvailableProviders) return "No Active Gateway";
    if (this.selectedProvider === "stripe") return "Stripe Selected";
    if (this.selectedProvider === "paypal") return "PayPal Selected";
    return "Authorize.Net Selected";
  }

  get authorizeNetStatusText() { return this.getProviderStatusText(this.authorizeNetConfig); }
  get stripeStatusText() { return this.getProviderStatusText(this.stripeConfig); }
  get paypalStatusText() { return this.getProviderStatusText(this.paypalConfig); }

  get showStripeLoader() { return this.isStripeSelected && this.isStripeInitializing; }
  get showPaypalLoader() { return this.isPaypalSelected && this.isPaypalInitializing; }

  get paypalPreviewMessage() {
    return this.canRenderPayPalButtons
      ? "Complete checkout using the PayPal button below."
      : "PayPal will appear here once the current PayPal configuration is active.";
  }

  get paypalStatusMessage() { return this.canRenderPayPalButtons ? "" : this.paypalConfig?.message || ""; }
  get showPaypalStatusMessage() { return !!this.paypalStatusMessage; }

  get proceedButtonLabel() {
    if (this.isSubmitting) return "Processing...";
    if (this.selectedProvider === "stripe") return "Proceed with Stripe";
    if (this.selectedProvider === "paypal") return "Pay with PayPal";
    return "Proceed with Authorize.Net";
  }

  get isProceedDisabled() {
    if (!this.hasAvailableProviders) return true;
    if (this.selectedProvider === "paypal") return true;
    return this.isSubmitting || this.showStripeLoader || !this.hasValidAmount() || !this.isProviderSelectable(this.selectedProvider);
  }

  getProviderTileClass(providerName) {
    const classes = ["provider-tile"];
    if (this.selectedProvider === providerName) classes.push("provider-tile-selected");
    if (!this.isProviderSelectable(providerName)) classes.push("provider-tile-disabled");
    return classes.join(" ");
  }

  async initializeProviderConfigs() {
    try {
      const serverResponseStr = await getActiveGatewaysForCheckout();
      const serverResponse = JSON.parse(serverResponseStr);

      if (serverResponse.status !== 'Success') {
        this.selectedProvider = null; // Reset
        this.dispatchError(serverResponse.message || "Failed to validate credentials with Server Org.");
        this.authorizeNetConfig = this.buildUnavailableProviderConfig(serverResponse.message);
        this.stripeConfig = this.buildUnavailableProviderConfig(serverResponse.message);
        this.paypalConfig = this.buildUnavailableProviderConfig(serverResponse.message);
        return;
      }

      const activeGateways = (serverResponse.activeGateways || []).map(g => g.toLowerCase().trim());

      const [authorizeNetResult, stripeResult, paypalResult] = await Promise.allSettled([
        getAuthorizeNetClientConfig(),
        getStripeClientConfig(),
        getPayPalClientConfig(),
      ]);

      // Intersection Logic
      this.authorizeNetConfig = authorizeNetResult.status === "fulfilled"
        ? { ...authorizeNetResult.value, active: authorizeNetResult.value.active && activeGateways.includes("authorize.net") }
        : this.buildUnavailableProviderConfig("Authorize.Net configuration could not be loaded.", authorizeNetResult.reason);

      this.stripeConfig = stripeResult.status === "fulfilled"
        ? { ...stripeResult.value, active: stripeResult.value.active && activeGateways.includes("stripe") }
        : this.buildUnavailableProviderConfig("Stripe configuration could not be loaded.", stripeResult.reason);

      this.paypalConfig = paypalResult.status === "fulfilled"
        ? { ...paypalResult.value, active: paypalResult.value.active && activeGateways.includes("paypal") }
        : this.buildUnavailableProviderConfig("PayPal configuration could not be loaded.", paypalResult.reason);

      // Auto-select provider
      if (!this.isProviderSelectable(this.selectedProvider)) {
        if (this.isProviderSelectable("authorizenet")) this.selectedProvider = "authorizenet";
        else if (this.isProviderSelectable("stripe")) this.selectedProvider = "stripe";
        else if (this.isProviderSelectable("paypal")) this.selectedProvider = "paypal";
        else this.selectedProvider = null;
      }

      if (this.selectedProvider === "authorizenet" && this.isAuthorizeNetActive) this.primeAuthorizeNet();
      if (this.isStripeActive) this.preloadStripeInBackground();
      if (this.selectedProvider === "paypal" && this.canRenderPayPalButtons) this.primePayPal();

    } catch (error) {
      this.selectedProvider = null;
      this.dispatchError(this.getErrorMessage(error, "Failed to connect to Server Org."));
    }
  }

  buildUnavailableProviderConfig(message, error) {
    return {
      active: false,
      configured: false,
      message: this.getErrorMessage(error, message),
    };
  }

  isProviderSelectable(providerName) {
    if (providerName === "authorizenet") return this.isAuthorizeNetActive;
    if (providerName === "stripe") return this.isStripeActive;
    if (providerName === "paypal") return this.isPayPalActive;
    return false;
  }

  getDisabledProviderMessage(config) {
    return config?.active === true ? "" : "Subscribe to use this payment method.";
  }

  getProviderStatusText(config) {
    return config?.active === true ? "Available now" : "Unavailable";
  }

  handleProviderSelection(event) {
    const selected = this.getProviderFromEvent(event);
    if (!selected || selected === this.selectedProvider || !this.isProviderSelectable(selected)) return;

    if (this.selectedProvider === "stripe" && selected !== "stripe") this.unmountStripeCardElement();
    if (this.selectedProvider === "paypal" && selected !== "paypal") this.unmountPayPalButtons();

    this.selectedProvider = selected;
    this.applyProviderTestDefaults();
    this.clearPaymentBillingFields();

    if (this.selectedProvider === "stripe") {
      this.resetStripeDiagnostics();
      this.logStripeStep("Stripe provider selected");
      this.primeStripe();
    } else if (this.selectedProvider === "authorizenet") {
      this.primeAuthorizeNet();
    } else if (this.selectedProvider === "paypal") {
      this.primePayPal();
    }

    this.dispatchEvent(new CustomEvent("providerchange", { detail: { provider: this.selectedProvider } }));
  }

  applyProviderTestDefaults() {
    this.paymentForm = { ...this.paymentForm, cardNumber: "" };
  }

  async primeAuthorizeNet() {
    try { await this.ensureAuthorizeNetReady(); } catch (error) {}
  }

  async primeStripe() {
    this.isStripeInitializing = true;
    try {
      this.logStripeStep("Loading Stripe configuration and Stripe.js");
      await this.ensureStripeReady();
      this.logStripeStep("Stripe.js is ready");
      await this.waitForStripeMount();
    } catch (error) {
      this.isStripeInitializing = false;
      this.logStripeStep(`Stripe initialization failed: ${this.getErrorMessage(error)}`, error);
    }
  }

  async primePayPal() {
    if (!this.canRenderPayPalButtons) {
      this.isPaypalInitializing = false;
      return;
    }
    this.isPaypalInitializing = true;
    try {
      await this.ensurePayPalReady();
      await this.mountPayPalButtons();
    } catch (error) {
      this.isPaypalInitializing = false;
      this.dispatchError(this.getErrorMessage(error, "PayPal failed to initialize."));
    }
  }

  preloadStripeInBackground() {
    if (!this.isStripeActive || this.stripePreloadQueued || this.stripeReadyPromise || this.stripeInstance) return;
    this.stripePreloadQueued = true;
    const schedulePreload = typeof window.requestIdleCallback === "function"
        ? window.requestIdleCallback.bind(window)
        : (callback) => window.setTimeout(callback, 0);

    schedulePreload(() => {
      this.ensureStripeReady().catch(() => { this.stripeReadyPromise = null; });
    });
  }

  async waitForStripeMount(maxAttempts = 20, delayMs = 50) {
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      this.mountStripeCardElement();
      if (this.stripeCardMounted) {
        this.isStripeInitializing = false;
        return;
      }
      await new Promise((resolve) => { window.setTimeout(resolve, delayMs); });
    }
    this.isStripeInitializing = false;
    throw new Error("Stripe card entry could not be rendered.");
  }

  @api async handlesubmit(priceValue) {
    if (this.selectedProvider === "paypal") {
      this.dispatchError("Use the PayPal button to complete checkout.");
      return;
    }

    try {
      if (this.isSubmitting) return;
      this.isSubmitting = true;
      this.showErrorModal = false;
      const resolvedAmount = this.resolveAmount(priceValue);

      if (this.selectedProvider === "stripe") {
        this.resetStripeDiagnostics();
        this.logStripeStep(`Stripe submit started for amount ${resolvedAmount}`);
        await this.handleStripeSubmit(resolvedAmount);
      } else {
        await this.handleAuthorizeNetSubmit(resolvedAmount);
      }
    } catch (error) {
      this.dispatchError(this.getErrorMessage(error));
    } finally {
      this.isSubmitting = false;
    }
  }

  async handleProceedClick() {
    if (!this.hasAvailableProviders) {
      this.dispatchError("No payment option is available right now. Subscribe to use these services.");
      return;
    }
    await this.handlesubmit(this.amount);
  }

  resolveAmount(priceValue) {
    const candidate = priceValue != null ? priceValue : this.amount;
    const amount = Number(candidate);
    if (Number.isNaN(amount) || amount <= 0) {
      throw new Error("Payment amount is not available.");
    }
    return amount;
  }

  hasValidAmount() {
    const amount = Number(this.amount);
    return !Number.isNaN(amount) && amount > 0;
  }

  async handleAuthorizeNetSubmit(resolvedAmount) {
    const paymentDetails = this.collectPaymentDetails(resolvedAmount);
    if (this.errorReturnObj) {
      this.dispatchError(this.errorReturnObj.message);
      return;
    }

    const config = await this.ensureAuthorizeNetReady();
    const opaqueData = await this.tokenizePaymentData(config, paymentDetails);
    this.clearSensitiveFields();

    const response = await processAuthorizeNetPayment({
      request: {
        amount: Number(resolvedAmount),
        orderId: this.orderId || null,
        dataDescriptor: opaqueData.dataDescriptor,
        dataValue: opaqueData.dataValue,
        fullName: paymentDetails.cardName,
        address: paymentDetails.cardAddressOne,
        city: paymentDetails.cardCity,
        state: paymentDetails.cardState,
        zip: paymentDetails.cardZipCode,
        country: paymentDetails.cardCountry,
        transactionType: "authCaptureTransaction",
      },
    });

    if (!response?.success || !response?.transId) {
      this.dispatchError(response?.message || "Transaction Unsuccessful");
      return;
    }
    this.dispatchSuccess(response);
  }

  async handleStripeSubmit(resolvedAmount) {
    this.logStripeStep("Validating Stripe form fields");
    const paymentDetails = this.collectStripePaymentDetails(resolvedAmount);
    if (this.errorReturnObj) {
      this.logStripeStep(`Stripe validation failed: ${this.errorReturnObj.message}`);
      this.dispatchError(this.errorReturnObj.message);
      return;
    }

    this.logStripeStep("Ensuring Stripe.js resources are ready");
    await this.ensureStripeReady();
    if (!this.stripeCardElement) {
      this.logStripeStep("Mounting Stripe card element");
      this.mountStripeCardElement();
    }

    if (!this.stripeInstance || !this.stripeCardElement) {
      this.logStripeStep("Stripe card entry is not ready");
      throw new Error("Stripe card entry is not ready.");
    }

    this.logStripeStep("Creating Stripe PaymentMethod");
    const stripeResponse = await this.stripeInstance.createPaymentMethod({
      type: "card",
      card: this.stripeCardElement,
      billing_details: {
        name: paymentDetails.cardName,
        address: {
          line1: paymentDetails.cardAddressOne,
          city: paymentDetails.cardCity,
          state: paymentDetails.cardState,
          postal_code: paymentDetails.cardZipCode,
          country: paymentDetails.cardCountry,
        },
      },
    });

    if (stripeResponse?.error) {
      this.logStripeStep(`Stripe createPaymentMethod failed: ${stripeResponse.error.message || "Unknown error"}`);
      throw new Error(stripeResponse.error.message || "Stripe payment setup failed.");
    }

    this.logStripeStep(`Stripe PaymentMethod created: ${stripeResponse?.paymentMethod?.id || "missing id"}`);
    this.logStripeStep("Calling Apex StripePaymentService.processPayment");

    const response = await processStripePayment({
      request: {
        amount: Number(resolvedAmount),
        orderId: this.orderId || null,
        paymentMethodId: stripeResponse?.paymentMethod?.id,
        fullName: paymentDetails.cardName,
        address: paymentDetails.cardAddressOne,
        city: paymentDetails.cardCity,
        state: paymentDetails.cardState,
        zip: paymentDetails.cardZipCode,
        country: paymentDetails.cardCountry,
        currencyCode: "usd",
      },
    });

    this.logStripeStep(`Apex responded: success=${response?.success === true}, transId=${response?.transId || "n/a"}, message=${response?.message || "n/a"}`);

    if (!response?.success || !response?.transId) {
      this.dispatchError(response?.message || "Transaction Unsuccessful");
      return;
    }

    this.clearStripeSensitiveFields();
    this.logStripeStep("Stripe payment completed successfully");
    this.dispatchSuccess(response);
  }

  collectPaymentDetails(priceValue) {
    const cardName = this.template.querySelector(".Namecard");
    const cardNumber = this.template.querySelector(".cardNumber");
    const monthOptions = this.template.querySelector(".monthOptions");
    const yearOptions = this.template.querySelector(".yearOptions");
    const securityNumber = this.template.querySelector(".cvvNumber");
    const cardAddressOne = this.template.querySelector(".cardAddressValue");
    const cardCity = this.template.querySelector(".cardcity");
    const cardState = this.template.querySelector(".cardState");
    const cardZipCode = this.template.querySelector(".cardZip");
    const cardCountry = this.template.querySelector(".cardCountry");

    this.errorReturnObj = null;

    const firstError =
      this.validateCardNameField(cardName) ||
      this.validateCardNumberField(cardNumber) ||
      this.validateCvvField(securityNumber) ||
      this.validateExpiryFields(monthOptions, yearOptions) ||
      this.validateZipField(cardZipCode);

    if (firstError) {
      this.errorReturnObj = { message: firstError, resultCode: "Error" };
    }

    return {
      cardName: cardName?.value?.trim(),
      cardNumber: cardNumber?.value?.replace(/\s+/g, ""),
      cardMonth: String(monthOptions?.value || "").padStart(2, "0"),
      cardYear: String(yearOptions?.value || "").slice(-2),
      securityCode: securityNumber?.value?.trim(),
      total: priceValue,
      cardAddressOne: cardAddressOne?.value?.trim() || "",
      cardCity: cardCity?.value?.trim() || "",
      cardState: cardState?.value || "",
      cardZipCode: cardZipCode?.value?.trim() || "",
      cardCountry: cardCountry?.value?.trim() || "",
    };
  }

  collectStripePaymentDetails(priceValue) {
    const cardName = this.template.querySelector(".Namecard");
    const cardAddressOne = this.template.querySelector(".cardAddressValue");
    const cardCity = this.template.querySelector(".cardcity");
    const cardState = this.template.querySelector(".cardState");
    const cardZipCode = this.template.querySelector(".cardZip");
    const cardCountry = this.template.querySelector(".cardCountry");

    this.errorReturnObj = null;

    const firstError =
      this.validateCardNameField(cardName) ||
      this.validateZipField(cardZipCode) ||
      this.validateStripeCardElement();

    if (firstError) {
      this.errorReturnObj = { message: firstError, resultCode: "Error" };
    }

    return {
      cardName: cardName?.value?.trim(),
      total: priceValue,
      cardAddressOne: cardAddressOne?.value?.trim() || "",
      cardCity: cardCity?.value?.trim() || "",
      cardState: cardState?.value || "",
      cardZipCode: cardZipCode?.value?.trim() || "",
      cardCountry: cardCountry?.value?.trim() || "",
    };
  }

  handleCardNameInput(event) {
    const value = event.target.value.replace(/\s{2,}/g, " ");
    event.target.value = value;
    this.updatePaymentForm("cardName", value);
  }

  handleCardNameBlur(event) { this.validateCardNameField(event.target); }

  handleCardNumberInput(event) {
    const digits = (event.target.value || "").replace(/\D/g, "").slice(0, 16);
    const value = digits.replace(/(.{4})/g, "$1 ").trim();
    event.target.value = value;
    this.updatePaymentForm("cardNumber", value);
  }

  handleCardNumberBlur(event) { this.validateCardNumberField(event.target); }

  handleCvvInput(event) {
    const value = (event.target.value || "").replace(/\D/g, "").slice(0, 4);
    event.target.value = value;
    this.updatePaymentForm("securityCode", value);
  }

  handleCvvBlur(event) { this.validateCvvField(event.target); }

  handleZipInput(event) {
    const value = (event.target.value || "").replace(/[^a-zA-Z0-9\-\s]/g, "").slice(0, 20);
    event.target.value = value;
    this.updatePaymentForm("cardZipCode", value);
  }

  handleZipBlur(event) { this.validateZipField(event.target); }

  handleExpiryChange(event) {
    if (event?.target?.classList?.contains("monthOptions")) this.updatePaymentForm("cardMonth", event.target.value || "");
    if (event?.target?.classList?.contains("yearOptions")) this.updatePaymentForm("cardYear", event.target.value || "");

    const monthField = this.template.querySelector(".monthOptions");
    const yearField = this.template.querySelector(".yearOptions");
    this.validateExpiryFields(monthField, yearField);
  }

  handleTextFieldChange(event) {
    const fieldName = event.target?.dataset?.field;
    if (!fieldName) return;
    this.updatePaymentForm(fieldName, event.target.value || "");
  }

  updatePaymentForm(fieldName, value) {
    this.paymentForm = { ...this.paymentForm, [fieldName]: value };
    sessionStorage.setItem(FORM_CACHE_KEY, JSON.stringify(this.paymentForm));
  }

  validateCardNameField(field) {
    if (!field) return "Card Name is missing";
    const value = (field.value || "").trim();
    let message = "";
    if (!value) message = "Card Name is missing";
    else if (value.length < 2) message = "Enter the full cardholder name";
    else if (!/^[a-zA-Z .,'-]{2,64}$/.test(value)) message = "Enter a valid cardholder name";

    field.setCustomValidity(message);
    field.reportValidity();
    return message;
  }

  validateCardNumberField(field) {
    if (!field) return "Card Number is missing";
    const digits = (field.value || "").replace(/\D/g, "");
    let message = "";
    if (!digits) message = "Card Number is missing";
    else if (digits.length < 13 || digits.length > 16) message = "Enter a valid card number";
    else if (!this.isValidCardNumber(digits)) message = "Enter a valid card number";

    field.setCustomValidity(message);
    field.reportValidity();
    return message;
  }

  validateCvvField(field) {
    if (!field) return "Security Number is missing";
    const value = (field.value || "").trim();
    let message = "";
    if (!value) message = "Security Number is missing";
    else if (!/^\d{3,4}$/.test(value)) message = "Enter a valid CVV";

    field.setCustomValidity(message);
    field.reportValidity();
    return message;
  }

  validateExpiryFields(monthField, yearField) {
    const monthValue = monthField?.value;
    const yearValue = yearField?.value;
    let message = "";

    if (!monthValue) message = "Card Month is missing";
    else if (!yearValue) message = "Card Year is missing";
    else {
      const monthNumber = Number(monthValue);
      const yearNumber = Number(yearValue);
      const today = new Date();
      const currentMonth = today.getMonth() + 1;
      const currentYear = today.getFullYear();

      if (Number.isNaN(monthNumber) || monthNumber < 1 || monthNumber > 12) message = "Enter a valid expiry month";
      else if (Number.isNaN(yearNumber) || yearNumber < currentYear || yearNumber > currentYear + 20) message = "Enter a valid expiry year";
      else if (yearNumber === currentYear && monthNumber < currentMonth) message = "Card expiry date must be in the future";
    }

    if (monthField) {
      monthField.setCustomValidity(message === "Card Month is missing" || message === "Enter a valid expiry month" ? message : "");
      monthField.reportValidity();
    }
    if (yearField) {
      yearField.setCustomValidity(message === "Card Year is missing" || message === "Enter a valid expiry year" || message === "Card expiry date must be in the future" ? message : "");
      yearField.reportValidity();
    }
    return message;
  }

  validateZipField(field) {
    if (!field) return "";
    const value = (field.value || "").trim();
    let message = "";
    if (value && !/^[a-zA-Z0-9\-\s]{3,20}$/.test(value)) message = "Enter a valid ZIP or postal code";
    field.setCustomValidity(message);
    field.reportValidity();
    return message;
  }

  validateStripeCardElement() {
    if (!this.stripeCardMounted || !this.stripeCardElement) return "Stripe card details are not ready.";
    if (this.stripeCardError) return this.stripeCardError;
    if (!this.stripeCardComplete) {
      if (typeof this.stripeCardElement.focus === "function") this.stripeCardElement.focus();
      return "Enter the card number, expiry, and CVC in the Stripe card field.";
    }
    return "";
  }

  isValidCardNumber(cardNumber) {
    let sum = 0;
    let shouldDouble = false;
    for (let index = cardNumber.length - 1; index >= 0; index -= 1) {
      let digit = Number(cardNumber.charAt(index));
      if (shouldDouble) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      shouldDouble = !shouldDouble;
    }
    return sum % 10 === 0;
  }

  async ensureAuthorizeNetReady() {
    if (!this.authorizeNetReadyPromise) {
      this.authorizeNetReadyPromise = this.loadAuthorizeNetResources().catch((error) => {
        this.authorizeNetReadyPromise = null;
        throw error;
      });
    }
    return this.authorizeNetReadyPromise;
  }

  async loadAuthorizeNetResources() {
    if (!this.authorizeNetConfig) this.authorizeNetConfig = await getAuthorizeNetClientConfig();
    if (this.authorizeNetConfig?.active === false) throw new Error(this.authorizeNetConfig?.message || "Authorize.Net is currently inactive.");
    if (!this.authorizeNetConfig?.configured) throw new Error(this.authorizeNetConfig?.message || "Authorize.Net is not fully configured.");

    const libraryUrl = this.authorizeNetConfig.acceptJsUrl;
    if (!libraryUrl) throw new Error("Authorize.Net script URL is missing.");

    if (window.Accept && this.authorizeNetLibraryUrl === libraryUrl) return this.authorizeNetConfig;

    if (!acceptJsPromise || this.authorizeNetLibraryUrl !== libraryUrl) {
      this.authorizeNetLibraryUrl = libraryUrl;
      acceptJsPromise = this.loadExternalScript(libraryUrl);
    }

    await acceptJsPromise;
    await this.waitForAcceptGlobal();
    return this.authorizeNetConfig;
  }

  async ensureStripeReady() {
    if (!this.stripeReadyPromise) {
      this.stripeReadyPromise = this.loadStripeResources().catch((error) => {
        this.stripeReadyPromise = null;
        throw error;
      });
    }
    return this.stripeReadyPromise;
  }

  async loadStripeResources() {
    if (!this.stripeConfig) {
      try { this.stripeConfig = await getStripeClientConfig(); } catch (error) { throw new Error(this.getErrorMessage(error)); }
    }
    if (this.stripeConfig?.active === false) throw new Error(this.stripeConfig?.message || "Stripe is currently inactive.");
    if (!this.stripeConfig?.configured) throw new Error(this.stripeConfig?.message || "Stripe is not fully configured.");
    if (!this.stripeConfig?.publishableKey) throw new Error("Stripe publishable key is missing.");

    const libraryUrl = this.stripeConfig.stripeJsUrl;
    if (!libraryUrl) throw new Error("Stripe script URL is missing.");

    if (window.Stripe && this.stripeJsUrl === libraryUrl && this.stripeInstance) return this.stripeConfig;

    if (!stripeJsPromise || this.stripeJsUrl !== libraryUrl) {
      this.stripeJsUrl = libraryUrl;
      stripeJsPromise = this.loadStripeScript(libraryUrl);
    }

    await stripeJsPromise;
    await this.waitForStripeGlobal();
    this.stripeInstance = window.Stripe(this.stripeConfig.publishableKey);
    if (!this.stripeInstance) throw new Error("Stripe did not initialize correctly.");
    return this.stripeConfig;
  }

  async ensurePayPalReady() {
    if (!this.paypalReadyPromise) {
      this.paypalReadyPromise = this.loadPayPalResources().catch((error) => {
        this.paypalReadyPromise = null;
        throw error;
      });
    }
    return this.paypalReadyPromise;
  }

  async loadPayPalResources() {
    if (!this.paypalConfig) this.paypalConfig = await getPayPalClientConfig();
    if (this.paypalConfig?.active === false) throw new Error(this.paypalConfig?.message || "PayPal is currently inactive.");
    if (!this.paypalConfig?.configured) throw new Error(this.paypalConfig?.message || "PayPal is not fully configured.");

    const libraryUrl = this.paypalConfig.payPalJsUrl;
    if (!libraryUrl) throw new Error("PayPal script URL is missing.");
    if (window.paypal && this.paypalJsUrl === libraryUrl) return this.paypalConfig;

    if (!paypalJsPromise || this.paypalJsUrl !== libraryUrl) {
      this.paypalJsUrl = libraryUrl;
      paypalJsPromise = this.loadPayPalScript(libraryUrl);
    }

    await paypalJsPromise;
    await this.waitForPayPalGlobal();
    return this.paypalConfig;
  }

  waitForAcceptGlobal(maxWaitMs = 3000, intervalMs = 50) {
    return new Promise((resolve, reject) => {
      if (window.Accept && typeof window.Accept.dispatchData === "function") { resolve(); return; }
      let elapsed = 0;
      const timer = setInterval(() => {
        elapsed += intervalMs;
        if (window.Accept && typeof window.Accept.dispatchData === "function") { clearInterval(timer); resolve(); }
        else if (elapsed >= maxWaitMs) { clearInterval(timer); reject(new Error("Authorize.Net library did not initialize correctly.")); }
      }, intervalMs);
    });
  }

  waitForStripeGlobal(maxWaitMs = 3000, intervalMs = 50) {
    return new Promise((resolve, reject) => {
      if (window.Stripe && typeof window.Stripe === "function") { resolve(); return; }
      let elapsed = 0;
      const timer = setInterval(() => {
        elapsed += intervalMs;
        if (window.Stripe && typeof window.Stripe === "function") { clearInterval(timer); resolve(); }
        else if (elapsed >= maxWaitMs) { clearInterval(timer); reject(new Error("Stripe library did not initialize correctly.")); }
      }, intervalMs);
    });
  }

  waitForPayPalGlobal(maxWaitMs = 3000, intervalMs = 50) {
    return new Promise((resolve, reject) => {
      if (window.paypal && typeof window.paypal.Buttons === "function") { resolve(); return; }
      let elapsed = 0;
      const timer = setInterval(() => {
        elapsed += intervalMs;
        if (window.paypal && typeof window.paypal.Buttons === "function") { clearInterval(timer); resolve(); }
        else if (elapsed >= maxWaitMs) { clearInterval(timer); reject(new Error("PayPal library did not initialize correctly.")); }
      }, intervalMs);
    });
  }

  loadExternalScript(url) {
    return new Promise((resolve, reject) => {
      const existingScript = document.querySelector(`script[data-authorize-net-src="${url}"]`);
      if (existingScript) {
        if (window.Accept && typeof window.Accept.dispatchData === "function") { resolve(); return; }
        existingScript.addEventListener("load", () => resolve(), { once: true });
        existingScript.addEventListener("error", () => reject(new Error("Failed to load Authorize.Net library.")), { once: true });
        return;
      }
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.charset = "utf-8";
      script.dataset.authorizeNetSrc = url;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error("Failed to load Authorize.Net library."));
      document.head.appendChild(script);
    });
  }

  loadStripeScript(url) {
    return new Promise((resolve, reject) => {
      const existingScript = document.querySelector(`script[data-stripe-src="${url}"]`);
      if (existingScript) {
        if (window.Stripe && typeof window.Stripe === "function") { resolve(); return; }
        existingScript.addEventListener("load", () => resolve(), { once: true });
        existingScript.addEventListener("error", () => reject(new Error("Failed to load Stripe library.")), { once: true });
        return;
      }
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.charset = "utf-8";
      script.dataset.stripeSrc = url;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error("Failed to load Stripe library."));
      document.head.appendChild(script);
    });
  }

  loadPayPalScript(url) {
    return new Promise((resolve, reject) => {
      const existingScript = document.querySelector(`script[data-paypal-src="${url}"]`);
      if (existingScript) {
        if (window.paypal && typeof window.paypal.Buttons === "function") { resolve(); return; }
        existingScript.addEventListener("load", () => resolve(), { once: true });
        existingScript.addEventListener("error", () => reject(new Error("Failed to load PayPal library.")), { once: true });
        return;
      }
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.charset = "utf-8";
      script.dataset.paypalSrc = url;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error("Failed to load PayPal library."));
      document.head.appendChild(script);
    });
  }

  async mountPayPalButtons() {
    const host = this.template.querySelector(".paypal-button-container");
    if (!host || this.paypalButtonsMounted) return;

    this.isPaypalInitializing = true;
    await this.ensurePayPalReady();

    host.innerHTML = "";
    this.paypalButtonsInstance = window.paypal.Buttons({
      createOrder: async () => {
        const resolvedAmount = this.resolveAmount(this.amount);
        this.isSubmitting = true;

        const response = await createPayPalOrder({
          request: {
            amount: Number(resolvedAmount),
            orderId: this.orderId || null,
            fullName: this.paymentForm.cardName,
            address: this.paymentForm.cardAddressOne,
            city: this.paymentForm.cardCity,
            state: this.paymentForm.cardState,
            zip: this.paymentForm.cardZipCode,
            country: this.paymentForm.cardCountry,
            currencyCode: "USD",
          },
        });

        if (!response?.success || !response?.paypalOrderId) throw new Error(response?.message || "PayPal order creation failed.");
        return response.paypalOrderId;
      },
      onApprove: async (data) => {
        try {
          const response = await capturePayPalOrder({
            request: {
              paypalOrderId: data?.orderID,
              orderId: this.orderId || null,
            },
          });
          if (!response?.success || !response?.transId) {
            this.dispatchError(response?.message || "PayPal capture failed.");
            return;
          }
          this.dispatchSuccess({ ...response, message: response.message || "Transaction Successful", resultCode: response.resultCode || "Ok" });
        } finally {
          this.isSubmitting = false;
        }
      },
      onCancel: () => { this.isSubmitting = false; },
      onError: (error) => {
        this.isSubmitting = false;
        this.dispatchError(this.getErrorMessage(error, "PayPal checkout failed."));
      },
    });

    await this.paypalButtonsInstance.render(host);
    this.paypalButtonsMounted = true;
    this.isPaypalInitializing = false;
  }

  unmountPayPalButtons() {
    const host = this.template.querySelector(".paypal-button-container");
    if (host) host.innerHTML = "";
    if (this.paypalButtonsInstance && typeof this.paypalButtonsInstance.close === "function") this.paypalButtonsInstance.close();
    this.paypalButtonsInstance = null;
    this.paypalButtonsMounted = false;
    this.isPaypalInitializing = false;
  }

  mountStripeCardElement() {
    const host = this.template.querySelector(".stripe-card-element");
    if (!host || !this.stripeInstance || this.stripeCardMounted) return;

    const elements = this.stripeInstance.elements();
    this.stripeCardElement = elements.create("card", {
      hidePostalCode: true,
      style: {
        base: { color: "#1f2a44", fontFamily: 'Arial, sans-serif', fontSize: "16px", "::placeholder": { color: "#6b7280" } },
        invalid: { color: "#c23934" },
      },
    });
    this.stripeCardElement.mount(host);
    this.stripeCardMounted = true;
    this.stripeCardComplete = false;
    this.stripeCardError = "";
    this.isStripeInitializing = false;
    this.logStripeStep("Stripe card element mounted");
    this.stripeCardElement.on("change", (event) => {
      this.stripeCardComplete = !!event.complete;
      this.stripeCardError = event.error?.message || "";
      if (event.error?.message) this.logStripeStep(`Stripe card error: ${event.error.message}`);
      else if (event.complete) this.logStripeStep("Stripe card details are complete");
    });
  }

  unmountStripeCardElement() {
    if (this.stripeCardElement) {
      this.stripeCardElement.unmount();
      this.stripeCardElement = null;
    }
    this.stripeCardMounted = false;
    this.stripeCardComplete = false;
    this.stripeCardError = "";
    this.isStripeInitializing = false;
  }

  tokenizePaymentData(config, paymentDetails) {
    return new Promise((resolve, reject) => {
      const secureData = {
        authData: { clientKey: config.publicClientKey, apiLoginID: config.apiLoginId },
        cardData: {
          cardNumber: paymentDetails.cardNumber, month: paymentDetails.cardMonth, year: paymentDetails.cardYear,
          cardCode: paymentDetails.securityCode, zip: paymentDetails.cardZipCode, fullName: paymentDetails.cardName,
        },
      };

      window.Accept.dispatchData(secureData, (response) => {
        if (response?.messages?.resultCode === "Error") {
          const errorMessages = (response.messages.message || []).map((item) => item.text).filter((item) => !!item).join(" ");
          reject(new Error(errorMessages || "Payment tokenization failed."));
          return;
        }
        if (!response?.opaqueData?.dataDescriptor || !response?.opaqueData?.dataValue) {
          reject(new Error("Payment tokenization failed."));
          return;
        }
        resolve(response.opaqueData);
      });
    });
  }

  clearSensitiveFields() {
    this.paymentForm = { ...this.paymentForm, cardNumber: "", securityCode: "" };
  }

  clearStripeSensitiveFields() {
    if (this.stripeCardElement) this.stripeCardElement.clear();
    this.stripeCardComplete = false;
    this.stripeCardError = "";
  }

  closeSuccessModal() {
    this.showSuccessModal = false;
    this.dispatchEvent(new CustomEvent("successmodalclose"));
  }

  closeErrorModal() { this.showErrorModal = false; }

  resetStripeDiagnostics() {
    this.stripeDebugMessages = [];
    this.stripeLastStep = "Idle";
  }

  logStripeStep(message, payload) {
    this.stripeLastStep = message;
    this.stripeDebugMessages = [...this.stripeDebugMessages, message];
  }

  dispatchSuccess(response) {
    sessionStorage.removeItem(FORM_CACHE_KEY);
    if (this.selectedProvider === "stripe") this.logStripeStep("Dispatching Stripe success event", response);

    this.successDetails = {
      message: response.message || "Transaction Successful", transId: response.transId || "",
      authCode: response.authCode || "", resultCode: response.resultCode || "Ok",
    };
    this.showSuccessModal = true;

    this.dispatchEvent(new CustomEvent("success", {
      detail: {
        resultCode: response.resultCode || "Ok", message: response.message || "Transaction Successful",
        transId: response.transId, provider: this.selectedProvider, authCode: response.authCode,
      },
    }));
  }

  dispatchError(message) {
    if (this.selectedProvider === "stripe") this.logStripeStep(`Dispatching Stripe error: ${message}`);
    this.errorDetails = {
      message, provider: this.selectedProvider,
      step: this.selectedProvider === "stripe" ? this.stripeLastStep : "Payment failed",
    };
    this.showErrorModal = true;

    this.dispatchEvent(new CustomEvent("error", { detail: { message, resultCode: "Error" } }));
  }

  getErrorMessage(errorOrMessage, fallbackMessage = "Something went wrong. Please try again.") {
    if (typeof errorOrMessage === "string") return errorOrMessage || fallbackMessage;
    const body = errorOrMessage?.body;
    if (typeof body?.message === "string" && body.message) return body.message;
    if (Array.isArray(body) && body.length > 0) {
      const bodyMessages = body.map((item) => item?.message).filter((message) => typeof message === "string" && message);
      if (bodyMessages.length > 0) return bodyMessages.join(" ");
    }
    if (Array.isArray(body?.pageErrors) && body.pageErrors.length > 0) {
      const pageErrorMessages = body.pageErrors.map((item) => item?.message).filter((message) => typeof message === "string" && message);
      if (pageErrorMessages.length > 0) return pageErrorMessages.join(" ");
    }
    if (typeof body?.exceptionType === "string" && typeof body?.message === "string" && body.message) return `${body.exceptionType}: ${body.message}`;
    if (typeof errorOrMessage?.message === "string" && errorOrMessage.message) return errorOrMessage.message;
    return fallbackMessage;
  }

  getProviderFromEvent(event) {
    let el = event?.currentTarget || event?.target;
    while (el && !(el.dataset && el.dataset.provider)) el = el.parentElement;
    return el?.dataset?.provider || null;
  }

  clearPaymentBillingFields() {
    this.paymentForm = {
      ...this.paymentForm, cardName: '', cardNumber: '', securityCode: '', cardMonth: '', cardYear: '',
      cardAddressOne: '', cardCity: '', cardState: '', cardZipCode: '', cardCountry: ''
    };
  }

  handleCancelClick() { this.showCancelWarningModal = true; }

  closeWarningModal() { this.showCancelWarningModal = false; }

  confirmCancel() {
    this.showCancelWarningModal = false;
    sessionStorage.removeItem(FORM_CACHE_KEY);
    this.dispatchEvent(new CustomEvent("cancelpayment"));
  }
}