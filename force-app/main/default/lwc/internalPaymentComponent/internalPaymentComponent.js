import { LightningElement, api } from "lwc";
import getCheckoutProviders from "@salesforce/apex/PaymentCheckoutController.getCheckoutProviders";
import initializePayment from "@salesforce/apex/PaymentCheckoutController.initializePayment";
import executePayment from "@salesforce/apex/PaymentCheckoutController.executePayment";
import CardPayment_lables from "@salesforce/label/c.CardPayment_lables";

let acceptJsPromise;
let stripeJsPromise;
let paypalJsPromise;

const SUPPORTED_RENDERER_MODES = new Set([
  "acceptJs",
  "stripeElements",
  "paypalButtons",
  "hosted"
]);

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
    cardCountry: ""
  };

  authorizeNetReadyPromise;
  authorizeNetLibraryUrl;
  stripeCardComplete = false;
  stripeCardElement;
  stripeCardError = "";
  stripeCardMounted = false;
  stripeInstance;
  stripeJsUrl;
  stripeReadyPromise;
  stripePreloadQueued = false;
  paypalJsUrl;
  paypalReadyPromise;
  paypalButtonsMounted = false;
  paypalButtonsInstance;
  isPaypalInitializing = false;
  isSubmitting = false;
  paymentProviderDescriptors = [];
  providerConfigs = {};

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

    this.initializeProviderConfigs();
  }

  renderedCallback() {
    if (
      this.selectedRendererMode === "stripeElements" &&
      this.stripeInstance &&
      !this.stripeCardMounted &&
      !this.isStripeInitializing
    ) {
      this.mountStripeCardElement();
    }
    if (
      this.selectedRendererMode === "paypalButtons" &&
      this.canRenderPayPalButtons &&
      !this.paypalButtonsMounted &&
      !this.isPaypalInitializing
    ) {
      this.mountPayPalButtons();
    }
  }

  disconnectedCallback() {
    this.clearSensitiveFields();
    this.unmountStripeCardElement();
    this.unmountPayPalButtons();
  }

  stateValues = [
    { label: "AK", value: "AK" },
    { label: "AL", value: "AL" },
    { label: "AR", value: "AR" },
    { label: "CA", value: "CA" },
    { label: "FL", value: "FL" },
    { label: "NY", value: "NY" },
    { label: "TX", value: "TX" },
    { label: "Outside US/Canada", value: "Outside US/Canada" }
  ];

  get selectedActionType() {
    return this.getProviderConfig(this.selectedProvider)?.actionType || null;
  }
  get selectedRendererMode() {
    return (
      this.getProviderConfig(this.selectedProvider)?.rendererMode || "hosted"
    );
  }
  get isCardMode() {
    return (
      this.selectedRendererMode === "acceptJs" ||
      this.selectedRendererMode === "stripeElements"
    );
  }
  get isButtonMode() {
    return this.selectedRendererMode === "paypalButtons";
  }
  get isHostedMode() {
    return !!this.selectedProvider && !this.isCardMode && !this.isButtonMode;
  }
  get isAcceptJsRenderer() {
    return this.selectedRendererMode === "acceptJs";
  }
  get isStripeElementsRenderer() {
    return this.selectedRendererMode === "stripeElements";
  }
  get hasAvailableProviders() {
    return this.availableProviderCount > 0;
  }
  get showUnavailableState() {
    return !this.hasAvailableProviders;
  }

  get availableProviderCount() {
    return this.paymentProviderTiles.length;
  }
  get paymentProviderTiles() {
    return this.paymentProviderDescriptors
      .filter((provider) => this.isProviderSelectable(provider.connectorKey))
      .map((provider) => ({
        key: provider.connectorKey,
        label: provider.label,
        logoText: this.getProviderLogoText(provider.connectorKey),
        logoClass: `tile-logo tile-logo-${provider.connectorKey}`,
        tileClass: this.getProviderTileClass(provider.connectorKey),
        statusText: this.getProviderStatusText(
          this.getProviderConfig(provider.connectorKey)
        )
      }));
  }

  get canRenderPayPalButtons() {
    const cfg = this.getProviderConfig(this.selectedProvider);
    return cfg?.active === true && cfg?.configured === true;
  }

  get stripeTestCardNumber() {
    return this.paymentForm.cardNumber || "";
  }

  get selectedProviderLabel() {
    if (!this.hasAvailableProviders) return "No Active Gateway";
    return `${this.getProviderLabel(this.selectedProvider)} Selected`;
  }

  get showStripeLoader() {
    return (
      this.selectedRendererMode === "stripeElements" &&
      this.isStripeInitializing
    );
  }
  get showPaypalLoader() {
    return (
      this.selectedRendererMode === "paypalButtons" && this.isPaypalInitializing
    );
  }

  get paypalPreviewMessage() {
    return this.canRenderPayPalButtons
      ? "Complete checkout using the PayPal button below."
      : "PayPal will appear here once the current PayPal configuration is active.";
  }

  get paypalStatusMessage() {
    return this.canRenderPayPalButtons
      ? ""
      : this.getProviderConfig(this.selectedProvider)?.message || "";
  }
  get showPaypalStatusMessage() {
    return !!this.paypalStatusMessage;
  }

  get proceedButtonLabel() {
    if (this.isSubmitting) return "Processing...";
    return (
      this.getProviderConfig(this.selectedProvider)?.buttonLabel ||
      `Continue with ${this.getProviderLabel(this.selectedProvider)}`
    );
  }

  get isProceedDisabled() {
    if (!this.hasAvailableProviders) return true;
    if (this.selectedRendererMode === "paypalButtons") return true;
    return (
      this.isSubmitting ||
      this.showStripeLoader ||
      !this.hasValidAmount() ||
      !this.isProviderSelectable(this.selectedProvider)
    );
  }

  getProviderTileClass(providerName) {
    const classes = ["provider-tile"];
    if (this.selectedProvider === providerName)
      classes.push("provider-tile-selected");
    if (!this.isProviderSelectable(providerName))
      classes.push("provider-tile-disabled");
    return classes.join(" ");
  }

  async initializeProviderConfigs() {
    try {
      const providers = await getCheckoutProviders();
      this.applyCheckoutProviders(providers);

      // Auto-select provider
      if (!this.isProviderSelectable(this.selectedProvider)) {
        const firstProvider = this.paymentProviderDescriptors.find((provider) =>
          this.isProviderSelectable(provider.connectorKey)
        );
        this.selectedProvider = firstProvider?.connectorKey || null;
      }

      this.primeSelectedProvider();
      this.preloadRendererInBackground("stripeElements");
    } catch (error) {
      this.selectedProvider = null;
      this.dispatchError(
        this.getErrorMessage(error, "Failed to connect to Server Org.")
      );
    }
  }

  applyCheckoutProviders(providers) {
    const providerList = Array.isArray(providers) ? providers : [];
    const normalized = providerList
      .filter((provider) => provider?.connectorKey)
      .map((provider) => ({
        ...provider,
        connectorKey: provider.connectorKey.toLowerCase()
      }))
      .sort((a, b) => (a.displayOrder || 999) - (b.displayOrder || 999));

    this.paymentProviderDescriptors = normalized.length
      ? normalized.map((provider) => ({
          ...provider,
          hasPayment: true,
          hasCheckout: true
        }))
      : [];

    this.providerConfigs = this.paymentProviderDescriptors.reduce(
      (acc, provider) => {
        acc[provider.connectorKey] = this.toProviderConfig(
          provider,
          `${provider.label || provider.connectorKey} is unavailable.`
        );
        return acc;
      },
      {}
    );
  }

  toProviderConfig(provider, fallbackMessage) {
    if (!provider) return this.buildUnavailableProviderConfig(fallbackMessage);
    return {
      ...(provider.config || {}),
      active: provider.active === true,
      configured: provider.configured === true,
      message: provider.message,
      actionType: provider.actionType || "hosted",
      rendererMode: this.normalizeRendererMode(
        provider.rendererMode || provider.actionType
      ),
      buttonLabel: provider.buttonLabel || provider.config?.buttonLabel,
      connectorKey: provider.connectorKey,
      label: provider.label,
      acceptJsUrl: provider.config?.acceptJsUrl || provider.clientScriptUrl,
      stripeJsUrl: provider.config?.stripeJsUrl || provider.clientScriptUrl,
      payPalJsUrl: provider.config?.payPalJsUrl || provider.clientScriptUrl,
      clientScriptUrl: provider.clientScriptUrl
    };
  }

  normalizeRendererMode(rendererMode) {
    return SUPPORTED_RENDERER_MODES.has(rendererMode) ? rendererMode : "hosted";
  }

  buildUnavailableProviderConfig(message, error) {
    return {
      active: false,
      configured: false,
      message: this.getErrorMessage(error, message)
    };
  }

  isProviderSelectable(providerName) {
    return this.getProviderConfig(providerName)?.active === true;
  }

  getProviderConfig(providerName) {
    return this.providerConfigs?.[providerName] || null;
  }

  providerKeyForRenderer(rendererMode) {
    if (
      this.getProviderConfig(this.selectedProvider)?.rendererMode ===
      rendererMode
    ) {
      return this.selectedProvider;
    }
    return this.paymentProviderDescriptors.find(
      (provider) =>
        this.getProviderConfig(provider.connectorKey)?.rendererMode ===
        rendererMode
    )?.connectorKey;
  }

  getProviderLabel(providerName) {
    const descriptor = this.paymentProviderDescriptors.find(
      (provider) => provider.connectorKey === providerName
    );
    return descriptor?.label || providerName || "Provider";
  }

  getProviderLogoText(providerName) {
    const label = this.getProviderLabel(providerName) || providerName || "?";
    const words = label
      .trim()
      .split(/[\s.]+/)
      .filter(Boolean);
    return words.length >= 2
      ? (words[0][0] + words[1][0]).toUpperCase()
      : label.slice(0, 2).toUpperCase();
  }

  getDisabledProviderMessage(config) {
    return config?.active === true
      ? ""
      : "Subscribe to use this payment method.";
  }

  getProviderStatusText(config) {
    return config?.active === true ? "Available now" : "Unavailable";
  }

  handleProviderSelection(event) {
    const selected = this.getProviderFromEvent(event);
    if (
      !selected ||
      selected === this.selectedProvider ||
      !this.isProviderSelectable(selected)
    )
      return;

    const previousMode = this.selectedRendererMode;
    if (previousMode === "stripeElements") this.unmountStripeCardElement();
    if (previousMode === "paypalButtons") this.unmountPayPalButtons();

    this.selectedProvider = selected;
    this.applyProviderTestDefaults();
    this.clearPaymentBillingFields();

    this.primeSelectedProvider();

    this.dispatchEvent(
      new CustomEvent("providerchange", {
        detail: { provider: this.selectedProvider }
      })
    );
  }

  applyProviderTestDefaults() {
    this.paymentForm = { ...this.paymentForm, cardNumber: "" };
  }

  async primeAuthorizeNet() {
    try {
      await this.ensureAuthorizeNetReady();
    } catch {
      // Authorize.Net readiness is surfaced when the user submits the payment.
    }
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
      this.logStripeStep(
        `Stripe initialization failed: ${this.getErrorMessage(error)}`,
        error
      );
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
      this.dispatchError(
        this.getErrorMessage(error, "PayPal failed to initialize.")
      );
    }
  }

  primeSelectedProvider() {
    if (this.selectedRendererMode === "acceptJs") {
      this.primeAuthorizeNet();
    } else if (this.selectedRendererMode === "stripeElements") {
      this.resetStripeDiagnostics();
      this.logStripeStep("Stripe provider selected");
      this.primeStripe();
    } else if (this.selectedRendererMode === "paypalButtons") {
      this.primePayPal();
    }
  }

  preloadRendererInBackground(rendererMode) {
    const provider = this.paymentProviderDescriptors.find(
      (descriptor) =>
        this.getProviderConfig(descriptor.connectorKey)?.rendererMode ===
          rendererMode &&
        this.getProviderConfig(descriptor.connectorKey)?.active === true
    );
    if (rendererMode === "stripeElements" && provider) {
      this.preloadStripeInBackground(provider.connectorKey);
    }
  }

  preloadStripeInBackground(providerKey = this.selectedProvider) {
    if (
      !this.getProviderConfig(providerKey)?.active ||
      this.stripePreloadQueued ||
      this.stripeReadyPromise ||
      this.stripeInstance
    )
      return;
    this.stripePreloadQueued = true;
    const schedulePreload =
      typeof window.requestIdleCallback === "function"
        ? window.requestIdleCallback.bind(window)
        : (callback) => window.setTimeout(callback, 0);

    schedulePreload(() => {
      this.ensureStripeReady().catch(() => {
        this.stripeReadyPromise = null;
      });
    });
  }

  async waitForStripeMount(maxAttempts = 20, delayMs = 50) {
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      this.mountStripeCardElement();
      if (this.stripeCardMounted) {
        this.isStripeInitializing = false;
        return;
      }
      await new Promise((resolve) => {
        window.setTimeout(resolve, delayMs);
      });
    }
    this.isStripeInitializing = false;
    throw new Error("Stripe card entry could not be rendered.");
  }

  @api async handlesubmit(priceValue) {
    if (this.selectedRendererMode === "paypalButtons") {
      this.dispatchError("Use the PayPal button to complete checkout.");
      return;
    }

    try {
      if (this.isSubmitting) return;
      this.isSubmitting = true;
      this.showErrorModal = false;
      const resolvedAmount = this.resolveAmount(priceValue);

      const rendererMode = this.selectedRendererMode;
      if (rendererMode === "stripeElements") {
        this.resetStripeDiagnostics();
        this.logStripeStep(
          `Stripe submit started for amount ${resolvedAmount}`
        );
        await this.handleStripeSubmit(resolvedAmount);
      } else if (rendererMode === "acceptJs") {
        await this.handleAuthorizeNetSubmit(resolvedAmount);
      } else {
        await this.handleHostedSubmit(resolvedAmount);
      }
    } catch (error) {
      this.dispatchError(this.getErrorMessage(error));
    } finally {
      this.isSubmitting = false;
    }
  }

  async handleProceedClick() {
    if (!this.hasAvailableProviders) {
      this.dispatchError(
        "No payment option is available right now. Subscribe to use these services."
      );
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

    const response = await executePayment({
      request: {
        providerKey: this.selectedProvider,
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
        transactionType: "authCaptureTransaction"
      }
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
      this.logStripeStep(
        `Stripe validation failed: ${this.errorReturnObj.message}`
      );
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
          country: paymentDetails.cardCountry
        }
      }
    });

    if (stripeResponse?.error) {
      this.logStripeStep(
        `Stripe createPaymentMethod failed: ${stripeResponse.error.message || "Unknown error"}`
      );
      throw new Error(
        stripeResponse.error.message || "Stripe payment setup failed."
      );
    }

    this.logStripeStep(
      `Stripe PaymentMethod created: ${stripeResponse?.paymentMethod?.id || "missing id"}`
    );
    this.logStripeStep("Calling Apex StripePaymentService.processPayment");

    const response = await executePayment({
      request: {
        providerKey: this.selectedProvider,
        amount: Number(resolvedAmount),
        orderId: this.orderId || null,
        paymentMethodId: stripeResponse?.paymentMethod?.id,
        fullName: paymentDetails.cardName,
        address: paymentDetails.cardAddressOne,
        city: paymentDetails.cardCity,
        state: paymentDetails.cardState,
        zip: paymentDetails.cardZipCode,
        country: paymentDetails.cardCountry,
        currencyCode: "usd"
      }
    });

    this.logStripeStep(
      `Apex responded: success=${response?.success === true}, transId=${response?.transId || "n/a"}, message=${response?.message || "n/a"}`
    );

    if (!response?.success || !response?.transId) {
      this.dispatchError(response?.message || "Transaction Unsuccessful");
      return;
    }

    this.clearStripeSensitiveFields();
    this.logStripeStep("Stripe payment completed successfully");
    this.dispatchSuccess(response);
  }

  async handleHostedSubmit(resolvedAmount) {
    const response = await initializePayment({
      request: {
        providerKey: this.selectedProvider,
        amount: Number(resolvedAmount),
        orderId: this.orderId || null
      }
    });
    if (!response?.success) {
      this.dispatchError(
        response?.message || "Hosted checkout could not be started."
      );
      return;
    }
    if (response.approveLink) {
      window.location.assign(response.approveLink);
      return;
    }
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
      cardCountry: cardCountry?.value?.trim() || ""
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
      cardCountry: cardCountry?.value?.trim() || ""
    };
  }

  handleCardNameInput(event) {
    const value = event.target.value.replace(/\s{2,}/g, " ");
    event.target.value = value;
    this.updatePaymentForm("cardName", value);
  }

  handleCardNameBlur(event) {
    this.validateCardNameField(event.target);
  }

  handleCardNumberInput(event) {
    const digits = (event.target.value || "").replace(/\D/g, "").slice(0, 16);
    const value = digits.replace(/(.{4})/g, "$1 ").trim();
    event.target.value = value;
    this.updatePaymentForm("cardNumber", value);
  }

  handleCardNumberBlur(event) {
    this.validateCardNumberField(event.target);
  }

  handleCvvInput(event) {
    const value = (event.target.value || "").replace(/\D/g, "").slice(0, 4);
    event.target.value = value;
    this.updatePaymentForm("securityCode", value);
  }

  handleCvvBlur(event) {
    this.validateCvvField(event.target);
  }

  handleZipInput(event) {
    const value = (event.target.value || "")
      .replace(/[^a-zA-Z0-9\-\s]/g, "")
      .slice(0, 20);
    event.target.value = value;
    this.updatePaymentForm("cardZipCode", value);
  }

  handleZipBlur(event) {
    this.validateZipField(event.target);
  }

  handleExpiryChange(event) {
    if (event?.target?.classList?.contains("monthOptions"))
      this.updatePaymentForm("cardMonth", event.target.value || "");
    if (event?.target?.classList?.contains("yearOptions"))
      this.updatePaymentForm("cardYear", event.target.value || "");

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
  }

  validateCardNameField(field) {
    if (!field) return "Card Name is missing";
    const value = (field.value || "").trim();
    let message = "";
    if (!value) message = "Card Name is missing";
    else if (value.length < 2) message = "Enter the full cardholder name";
    else if (!/^[a-zA-Z .,'-]{2,64}$/.test(value))
      message = "Enter a valid cardholder name";

    field.setCustomValidity(message);
    field.reportValidity();
    return message;
  }

  validateCardNumberField(field) {
    if (!field) return "Card Number is missing";
    const digits = (field.value || "").replace(/\D/g, "");
    let message = "";
    if (!digits) message = "Card Number is missing";
    else if (digits.length < 13 || digits.length > 16)
      message = "Enter a valid card number";
    else if (!this.isValidCardNumber(digits))
      message = "Enter a valid card number";

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

      if (Number.isNaN(monthNumber) || monthNumber < 1 || monthNumber > 12)
        message = "Enter a valid expiry month";
      else if (
        Number.isNaN(yearNumber) ||
        yearNumber < currentYear ||
        yearNumber > currentYear + 20
      )
        message = "Enter a valid expiry year";
      else if (yearNumber === currentYear && monthNumber < currentMonth)
        message = "Card expiry date must be in the future";
    }

    if (monthField) {
      monthField.setCustomValidity(
        message === "Card Month is missing" ||
          message === "Enter a valid expiry month"
          ? message
          : ""
      );
      monthField.reportValidity();
    }
    if (yearField) {
      yearField.setCustomValidity(
        message === "Card Year is missing" ||
          message === "Enter a valid expiry year" ||
          message === "Card expiry date must be in the future"
          ? message
          : ""
      );
      yearField.reportValidity();
    }
    return message;
  }

  validateZipField(field) {
    if (!field) return "";
    const value = (field.value || "").trim();
    let message = "";
    if (value && !/^[a-zA-Z0-9\-\s]{3,20}$/.test(value))
      message = "Enter a valid ZIP or postal code";
    field.setCustomValidity(message);
    field.reportValidity();
    return message;
  }

  validateStripeCardElement() {
    if (!this.stripeCardMounted || !this.stripeCardElement)
      return "Stripe card details are not ready.";
    if (this.stripeCardError) return this.stripeCardError;
    if (!this.stripeCardComplete) {
      if (typeof this.stripeCardElement.focus === "function")
        this.stripeCardElement.focus();
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
      this.authorizeNetReadyPromise = this.loadAuthorizeNetResources().catch(
        (error) => {
          this.authorizeNetReadyPromise = null;
          throw error;
        }
      );
    }
    return this.authorizeNetReadyPromise;
  }

  async loadAuthorizeNetResources() {
    let cfg = this.getProviderConfig(this.providerKeyForRenderer("acceptJs"));
    if (!cfg) {
      await this.initializeProviderConfigs();
      cfg = this.getProviderConfig(this.providerKeyForRenderer("acceptJs"));
    }
    if (cfg?.active === false)
      throw new Error(cfg?.message || "Authorize.Net is currently inactive.");
    if (!cfg?.configured)
      throw new Error(cfg?.message || "Authorize.Net is not fully configured.");

    const libraryUrl = cfg.acceptJsUrl;
    if (!libraryUrl) throw new Error("Authorize.Net script URL is missing.");

    if (window.Accept && this.authorizeNetLibraryUrl === libraryUrl) return cfg;

    if (!acceptJsPromise || this.authorizeNetLibraryUrl !== libraryUrl) {
      this.authorizeNetLibraryUrl = libraryUrl;
      acceptJsPromise = this.loadExternalScript(libraryUrl);
    }

    await acceptJsPromise;
    await this.waitForAcceptGlobal();
    return cfg;
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
    let cfg = this.getProviderConfig(
      this.providerKeyForRenderer("stripeElements")
    );
    if (!cfg) {
      await this.initializeProviderConfigs();
      cfg = this.getProviderConfig(
        this.providerKeyForRenderer("stripeElements")
      );
    }
    if (cfg?.active === false)
      throw new Error(cfg?.message || "Stripe is currently inactive.");
    if (!cfg?.configured)
      throw new Error(cfg?.message || "Stripe is not fully configured.");
    if (!cfg?.publishableKey)
      throw new Error("Stripe publishable key is missing.");

    const libraryUrl = cfg.stripeJsUrl;
    if (!libraryUrl) throw new Error("Stripe script URL is missing.");

    if (window.Stripe && this.stripeJsUrl === libraryUrl && this.stripeInstance)
      return cfg;

    if (!stripeJsPromise || this.stripeJsUrl !== libraryUrl) {
      this.stripeJsUrl = libraryUrl;
      stripeJsPromise = this.loadStripeScript(libraryUrl);
    }

    await stripeJsPromise;
    await this.waitForStripeGlobal();
    this.stripeInstance = window.Stripe(cfg.publishableKey);
    if (!this.stripeInstance)
      throw new Error("Stripe did not initialize correctly.");
    return cfg;
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
    let cfg = this.getProviderConfig(
      this.providerKeyForRenderer("paypalButtons")
    );
    if (!cfg) {
      await this.initializeProviderConfigs();
      cfg = this.getProviderConfig(
        this.providerKeyForRenderer("paypalButtons")
      );
    }
    if (cfg?.active === false)
      throw new Error(cfg?.message || "PayPal is currently inactive.");
    if (!cfg?.configured)
      throw new Error(cfg?.message || "PayPal is not fully configured.");

    const libraryUrl = cfg.payPalJsUrl;
    if (!libraryUrl) throw new Error("PayPal script URL is missing.");
    if (window.paypal && this.paypalJsUrl === libraryUrl) return cfg;

    if (!paypalJsPromise || this.paypalJsUrl !== libraryUrl) {
      this.paypalJsUrl = libraryUrl;
      paypalJsPromise = this.loadPayPalScript(libraryUrl);
    }

    await paypalJsPromise;
    await this.waitForPayPalGlobal();
    return cfg;
  }

  waitForAcceptGlobal(maxWaitMs = 3000, intervalMs = 50) {
    return new Promise((resolve, reject) => {
      if (window.Accept && typeof window.Accept.dispatchData === "function") {
        resolve();
        return;
      }
      let elapsed = 0;
      const timer = setInterval(() => {
        elapsed += intervalMs;
        if (window.Accept && typeof window.Accept.dispatchData === "function") {
          clearInterval(timer);
          resolve();
        } else if (elapsed >= maxWaitMs) {
          clearInterval(timer);
          reject(
            new Error("Authorize.Net library did not initialize correctly.")
          );
        }
      }, intervalMs);
    });
  }

  waitForStripeGlobal(maxWaitMs = 3000, intervalMs = 50) {
    return new Promise((resolve, reject) => {
      if (window.Stripe && typeof window.Stripe === "function") {
        resolve();
        return;
      }
      let elapsed = 0;
      const timer = setInterval(() => {
        elapsed += intervalMs;
        if (window.Stripe && typeof window.Stripe === "function") {
          clearInterval(timer);
          resolve();
        } else if (elapsed >= maxWaitMs) {
          clearInterval(timer);
          reject(new Error("Stripe library did not initialize correctly."));
        }
      }, intervalMs);
    });
  }

  waitForPayPalGlobal(maxWaitMs = 3000, intervalMs = 50) {
    return new Promise((resolve, reject) => {
      if (window.paypal && typeof window.paypal.Buttons === "function") {
        resolve();
        return;
      }
      let elapsed = 0;
      const timer = setInterval(() => {
        elapsed += intervalMs;
        if (window.paypal && typeof window.paypal.Buttons === "function") {
          clearInterval(timer);
          resolve();
        } else if (elapsed >= maxWaitMs) {
          clearInterval(timer);
          reject(new Error("PayPal library did not initialize correctly."));
        }
      }, intervalMs);
    });
  }

  loadExternalScript(url) {
    return new Promise((resolve, reject) => {
      const existingScript = document.querySelector(
        `script[data-authorize-net-src="${url}"]`
      );
      if (existingScript) {
        if (window.Accept && typeof window.Accept.dispatchData === "function") {
          resolve();
          return;
        }
        existingScript.addEventListener("load", () => resolve(), {
          once: true
        });
        existingScript.addEventListener(
          "error",
          () => reject(new Error("Failed to load Authorize.Net library.")),
          { once: true }
        );
        return;
      }
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.charset = "utf-8";
      script.dataset.authorizeNetSrc = url;
      script.onload = () => resolve();
      script.onerror = () =>
        reject(new Error("Failed to load Authorize.Net library."));
      document.head.appendChild(script);
    });
  }

  loadStripeScript(url) {
    return new Promise((resolve, reject) => {
      const existingScript = document.querySelector(
        `script[data-stripe-src="${url}"]`
      );
      if (existingScript) {
        if (window.Stripe && typeof window.Stripe === "function") {
          resolve();
          return;
        }
        existingScript.addEventListener("load", () => resolve(), {
          once: true
        });
        existingScript.addEventListener(
          "error",
          () => reject(new Error("Failed to load Stripe library.")),
          { once: true }
        );
        return;
      }
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.charset = "utf-8";
      script.dataset.stripeSrc = url;
      script.onload = () => resolve();
      script.onerror = () =>
        reject(new Error("Failed to load Stripe library."));
      document.head.appendChild(script);
    });
  }

  loadPayPalScript(url) {
    return new Promise((resolve, reject) => {
      const existingScript = document.querySelector(
        `script[data-paypal-src="${url}"]`
      );
      if (existingScript) {
        if (window.paypal && typeof window.paypal.Buttons === "function") {
          resolve();
          return;
        }
        existingScript.addEventListener("load", () => resolve(), {
          once: true
        });
        existingScript.addEventListener(
          "error",
          () => reject(new Error("Failed to load PayPal library.")),
          { once: true }
        );
        return;
      }
      const script = document.createElement("script");
      script.src = url;
      script.async = true;
      script.charset = "utf-8";
      script.dataset.paypalSrc = url;
      script.onload = () => resolve();
      script.onerror = () =>
        reject(new Error("Failed to load PayPal library."));
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

        const response = await initializePayment({
          request: {
            providerKey: this.selectedProvider,
            amount: Number(resolvedAmount),
            orderId: this.orderId || null,
            fullName: this.paymentForm.cardName,
            address: this.paymentForm.cardAddressOne,
            city: this.paymentForm.cardCity,
            state: this.paymentForm.cardState,
            zip: this.paymentForm.cardZipCode,
            country: this.paymentForm.cardCountry,
            currencyCode: "USD"
          }
        });

        if (!response?.success || !response?.paypalOrderId)
          throw new Error(response?.message || "PayPal order creation failed.");
        return response.paypalOrderId;
      },
      onApprove: async (data) => {
        try {
          const response = await executePayment({
            request: {
              providerKey: this.selectedProvider,
              paypalOrderId: data?.orderID,
              orderId: this.orderId || null
            }
          });
          if (!response?.success || !response?.transId) {
            this.dispatchError(response?.message || "PayPal capture failed.");
            return;
          }
          this.dispatchSuccess({
            ...response,
            message: response.message || "Transaction Successful",
            resultCode: response.resultCode || "Ok"
          });
        } finally {
          this.isSubmitting = false;
        }
      },
      onCancel: () => {
        this.isSubmitting = false;
      },
      onError: (error) => {
        this.isSubmitting = false;
        this.dispatchError(
          this.getErrorMessage(error, "PayPal checkout failed.")
        );
      }
    });

    await this.paypalButtonsInstance.render(host);
    this.paypalButtonsMounted = true;
    this.isPaypalInitializing = false;
  }

  unmountPayPalButtons() {
    const host = this.template.querySelector(".paypal-button-container");
    if (host) host.innerHTML = "";
    if (
      this.paypalButtonsInstance &&
      typeof this.paypalButtonsInstance.close === "function"
    )
      this.paypalButtonsInstance.close();
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
        base: {
          color: "#1f2a44",
          fontFamily: "Arial, sans-serif",
          fontSize: "16px",
          "::placeholder": { color: "#6b7280" }
        },
        invalid: { color: "#c23934" }
      }
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
      if (event.error?.message)
        this.logStripeStep(`Stripe card error: ${event.error.message}`);
      else if (event.complete)
        this.logStripeStep("Stripe card details are complete");
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
        authData: {
          clientKey: config.publicClientKey,
          apiLoginID: config.apiLoginId
        },
        cardData: {
          cardNumber: paymentDetails.cardNumber,
          month: paymentDetails.cardMonth,
          year: paymentDetails.cardYear,
          cardCode: paymentDetails.securityCode,
          zip: paymentDetails.cardZipCode,
          fullName: paymentDetails.cardName
        }
      };

      window.Accept.dispatchData(secureData, (response) => {
        if (response?.messages?.resultCode === "Error") {
          const errorMessages = (response.messages.message || [])
            .map((item) => item.text)
            .filter((item) => !!item)
            .join(" ");
          reject(new Error(errorMessages || "Payment tokenization failed."));
          return;
        }
        if (
          !response?.opaqueData?.dataDescriptor ||
          !response?.opaqueData?.dataValue
        ) {
          reject(new Error("Payment tokenization failed."));
          return;
        }
        resolve(response.opaqueData);
      });
    });
  }

  clearSensitiveFields() {
    this.paymentForm = {
      ...this.paymentForm,
      cardNumber: "",
      securityCode: ""
    };
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

  closeErrorModal() {
    this.showErrorModal = false;
  }

  resetStripeDiagnostics() {
    this.stripeDebugMessages = [];
    this.stripeLastStep = "Idle";
  }

  logStripeStep(message) {
    this.stripeLastStep = message;
    this.stripeDebugMessages = [...this.stripeDebugMessages, message];
  }

  dispatchSuccess(response) {
    if (this.selectedRendererMode === "stripeElements")
      this.logStripeStep("Dispatching Stripe success event", response);

    this.successDetails = {
      message: response.message || "Transaction Successful",
      transId: response.transId || "",
      authCode: response.authCode || "",
      resultCode: response.resultCode || "Ok"
    };
    this.showSuccessModal = true;

    this.dispatchEvent(
      new CustomEvent("success", {
        detail: {
          resultCode: response.resultCode || "Ok",
          message: response.message || "Transaction Successful",
          transId: response.transId,
          provider: this.selectedProvider,
          authCode: response.authCode
        }
      })
    );
  }

  dispatchError(message) {
    if (this.selectedRendererMode === "stripeElements")
      this.logStripeStep(`Dispatching Stripe error: ${message}`);
    this.errorDetails = {
      message,
      provider: this.selectedProvider,
      step:
        this.selectedRendererMode === "stripeElements"
          ? this.stripeLastStep
          : "Payment failed"
    };
    this.showErrorModal = true;

    this.dispatchEvent(
      new CustomEvent("error", { detail: { message, resultCode: "Error" } })
    );
  }

  getErrorMessage(
    errorOrMessage,
    fallbackMessage = "Something went wrong. Please try again."
  ) {
    if (typeof errorOrMessage === "string")
      return errorOrMessage || fallbackMessage;
    const body = errorOrMessage?.body;
    if (typeof body?.message === "string" && body.message) return body.message;
    if (Array.isArray(body) && body.length > 0) {
      const bodyMessages = body
        .map((item) => item?.message)
        .filter((message) => typeof message === "string" && message);
      if (bodyMessages.length > 0) return bodyMessages.join(" ");
    }
    if (Array.isArray(body?.pageErrors) && body.pageErrors.length > 0) {
      const pageErrorMessages = body.pageErrors
        .map((item) => item?.message)
        .filter((message) => typeof message === "string" && message);
      if (pageErrorMessages.length > 0) return pageErrorMessages.join(" ");
    }
    if (
      typeof body?.exceptionType === "string" &&
      typeof body?.message === "string" &&
      body.message
    )
      return `${body.exceptionType}: ${body.message}`;
    if (typeof errorOrMessage?.message === "string" && errorOrMessage.message)
      return errorOrMessage.message;
    return fallbackMessage;
  }

  getProviderFromEvent(event) {
    let el = event?.currentTarget || event?.target;
    while (el && !(el.dataset && el.dataset.provider)) el = el.parentElement;
    return el?.dataset?.provider || null;
  }

  clearPaymentBillingFields() {
    this.paymentForm = {
      ...this.paymentForm,
      cardName: "",
      cardNumber: "",
      securityCode: "",
      cardMonth: "",
      cardYear: "",
      cardAddressOne: "",
      cardCity: "",
      cardState: "",
      cardZipCode: "",
      cardCountry: ""
    };
  }

  handleCancelClick() {
    this.showCancelWarningModal = true;
  }

  closeWarningModal() {
    this.showCancelWarningModal = false;
  }

  confirmCancel() {
    this.showCancelWarningModal = false;
    this.dispatchEvent(new CustomEvent("cancelpayment"));
  }
}
