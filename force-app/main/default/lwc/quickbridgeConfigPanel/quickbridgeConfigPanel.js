import { LightningElement, track } from 'lwc';
import verifyCredentialsAndGetGateways from '@salesforce/apex/PaymentGatewayService.verifyCredentialsAndGetGateways';
import getPaymentMetadataConfigs from '@salesforce/apex/PaymentMetadataService.getPaymentMetadataConfigs';
import updatePaymentMetadata from '@salesforce/apex/PaymentMetadataService.updatePaymentMetadata';
import getConfigPanelPreferences from '@salesforce/apex/PaymentMetadataService.getConfigPanelPreferences';
import updateAvailableProductsVisible from '@salesforce/apex/PaymentMetadataService.updateAvailableProductsVisible';
import checkIntegrationExpiry from '@salesforce/apex/PaymentMetadataService.checkIntegrationExpiry';
import sendProductRenewalRequest from '@salesforce/apex/PaymentMetadataService.sendProductRenewalRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Authorize_Net_logo from '@salesforce/resourceUrl/Authorize_Net_logo';
import QuickBridge_Logo from '@salesforce/resourceUrl/QuickBridge_Logo';
import QB_Logo from '@salesforce/resourceUrl/QB_Logo';
import FedEx_Logo from '@salesforce/resourceUrl/FedEx_Logo';
import recoverPin from '@salesforce/apex/PaymentGatewayService.recoverPin';

const SESSION_KEY = 'qb_auth_session';
const TILE_PROVIDER_ALIASES = {
    qbo: ['qbo', 'quickbooks', 'quickbooksonline', 'quickbooks online'],
    shopify: ['shopify'],
    stripe: ['stripe'],
    authorizenet: ['authorizenet', 'authorize.net', 'authorize net', 'authnet'],
    paypal: ['paypal', 'pay pal'],
    fedex: ['fedex'],
    ups: ['ups']
};
const TILE_EXPIRY_FIELDS = {
    qbo: ['QuickBooks_End_Date__c'],
    shopify: ['Shopify_End_Date__c'],
    stripe: ['Stripe_End_Date__c'],
    authorizenet: ['AuthorizeNet_End_Date__c'],
    paypal: ['PayPal_EndDate__c'],
    fedex: ['FedEx_End_Date__c'],
    ups: ['UPS_End_Date__c']
};
const REPORTING_PRODUCT_KEYS = {
    qbo: 'quickbooks',
    shopify: 'shopify',
    stripe: 'stripe',
    authorizenet: 'authorizenet',
    paypal: 'paypal',
    fedex: 'fedex',
    ups: 'ups'
};

const TILE_START_FIELDS = {
    qbo: ['QuickBooks_Start_Date__c'],
    stripe: ['Stripe_Start_Date__c'],
    authorizenet: ['AuthorizeNet_Start_Date__c'],
    paypal: ['PayPal_StartDate__c'],
    fedex: ['FedEx_Start_Date__c'],     
    ups: ['UPS_Start_Date__c'],         
    shopify: ['Shopify_Start_Date__c'] 
};

export default class QuickbridgeConfigPanel extends LightningElement {
    @track currentScreen = 'login';
    @track isLoggingIn = false;
    @track isSaving = false;
    @track isRecoveringPin = false;
    @track availableProductsVisible = true;
    @track isSavingAvailableProductsPreference = false;
    @track integrationExpiryAlert = null;
    @track isRenewalModalOpen = false;
    @track isSendingRenewalEmail = false;
    @track renewalProducts = [];

    userId = '';
    recoverUserId = '';
    @track selectedTile = '';
    quickBridgeLogo = QuickBridge_Logo;

    allTilesDefinition = [
        { id: 'qbo', label: 'QuickBooks', logoUrl: QB_Logo },
        { id: 'shopify', label: 'Shopify', logoUrl: 'https://cdn.worldvectorlogo.com/logos/shopify.svg' },
        { id: 'stripe', label: 'Stripe', logoUrl: 'https://cdn.worldvectorlogo.com/logos/stripe-4.svg' },
        { id: 'authorizenet', label: 'Authorize.Net', logoUrl: Authorize_Net_logo },
        { id: 'paypal', label: 'PayPal', logoUrl: 'https://cdn.worldvectorlogo.com/logos/paypal-3.svg' },
        { id: 'fedex', label: 'FedEx', logoUrl: FedEx_Logo },
        { id: 'ups', label: 'UPS', logoUrl: 'https://cdn.worldvectorlogo.com/logos/ups-1.svg' }
    ];

    @track paymentMetadataConfigs = [];
    metadataFormValues = {};

    get isLoginScreen() { return this.currentScreen === 'login'; }
    get isTilesScreen() { return this.currentScreen === 'tiles'; }
    get isConfigScreen() { return this.currentScreen === 'config'; }
    get isForgotPinScreen() { return this.currentScreen === 'forgotPin'; }
    get isDashboardScreen() { return this.currentScreen === 'dashboard'; }
    get isReportingScreen() { return this.currentScreen === 'reporting'; }
    get isLoggedIn() { return this.currentScreen !== 'login' && this.currentScreen !== 'forgotPin'; }

    get isMappingScreen() { return this.currentScreen === 'mapping'; }
    get isQboSelected() { return this.selectedTile === 'qbo'; }
    get isStripeSelected() { return this.selectedTile === 'stripe'; }
    get isPayPalSelected() { return this.selectedTile === 'paypal'; }
    get isAuthNetSelected() { return this.selectedTile === 'authorizenet'; }
    get isShopify() { return this.selectedTile === 'shopify'; }
    get isFedExSelected() { return this.selectedTile === 'fedex'; }
    get isUPSSelected() { return this.selectedTile === 'ups'; }
    get isQboOrShopify() { return this.selectedTile === 'qbo' || this.selectedTile === 'shopify'; }
    get isSchedulerScreen() { return this.currentScreen === 'scheduler'; }
    get isSchedulerUnavailable() { return !this.isQboSelected && !this.isShopify; }

    get navHomeClass() { return this.currentScreen === 'tiles' ? 'nav-button active' : 'nav-button'; }
    get navDashboardClass() { return this.currentScreen === 'dashboard' ? 'nav-button active' : 'nav-button'; }
    get navReportingClass() { return this.currentScreen === 'reporting' ? 'nav-button active' : 'nav-button'; }
    get navMappingClass() { return this.currentScreen === 'mapping' ? 'nav-button active' : 'nav-button'; }
    get navSchedulerClass() { return this.currentScreen === 'scheduler' ? 'nav-button active' : 'nav-button'; }

    get subscribedTiles() {
        return this.allTilesDefinition.filter(tile => {
            const config = this.getConfigForTile(tile.id);
            return this.isConfigActiveAndCurrent(tile.id, config);
        });
    }

    get availableTiles() {
        return this.allTilesDefinition.filter(tile => {
            const config = this.getConfigForTile(tile.id);
            return !this.isConfigActiveAndCurrent(tile.id, config);
        });
    }

    isSubscribedTile(tileId) {
        return this.subscribedTiles.some(tile => tile.id === tileId);
    }

    get selectedReportingProductKey() {
        return REPORTING_PRODUCT_KEYS[this.selectedTile] || '';
    }

    get subscribedReportingProductKeys() {
        return this.subscribedTiles.map(tile => REPORTING_PRODUCT_KEYS[tile.id]).filter(Boolean);
    }

    get availableReportingProductKeys() {
        return this.availableTiles.map(tile => REPORTING_PRODUCT_KEYS[tile.id]).filter(Boolean);
    }

    navigateToScheduler() {
        if (this.isLoggedIn) {
            this.currentScreen = 'scheduler';
        }
    }

    get hasSubscribedTiles() {
        return this.subscribedTiles.length > 0;
    }

    get renewalExistingProducts() {
        return this.renewalProducts.filter(product => product.isSubscribed);
    }

    get renewalAdditionalProducts() {
        return this.renewalProducts.filter(product => !product.isSubscribed);
    }

    get hasRenewalExistingProducts() {
        return this.renewalExistingProducts.length > 0;
    }

    get hasRenewalAdditionalProducts() {
        return this.renewalAdditionalProducts.length > 0;
    }

    get hasRenewalSelections() {
        return this.renewalProducts.some(product => product.selected);
    }

    get renewalSubmitDisabled() {
        return this.isSendingRenewalEmail || !this.hasRenewalSelections;
    }

    get availableProductsToggleLabel() {
        return this.availableProductsVisible ? 'Hide' : 'Show';
    }

    get availableProductsToggleIcon() {
        return this.availableProductsVisible ? 'utility:hide' : 'utility:preview';
    }

    get availableProductsToggleTitle() {
        return this.availableProductsVisible ? 'Hide Available Products' : 'Show Available Products';
    }

    getConfigForTile(tileId) {
        const aliases = TILE_PROVIDER_ALIASES[tileId] || [tileId];
        return this.paymentMetadataConfigs.find(config => {
            const provider = (config.provider || '').toLowerCase().replace(/\s+/g, '');
            return aliases.some(alias => provider === alias.toLowerCase().replace(/\s+/g, ''));
        });
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
        const expiryFields = TILE_EXPIRY_FIELDS[tileId] || [];
        const expiryValue = expiryFields.map(field => fields[field]).find(value => value);
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
        const startFields = TILE_START_FIELDS[tileId] || [];
        const expiryFields = TILE_EXPIRY_FIELDS[tileId] || [];

        const startValue = startFields.map(field => fields[field]).find(value => value);
        const endValue = expiryFields.map(field => fields[field]).find(value => value);

        if (!startValue || !endValue) {
            return true; 
        }

        const startDate = new Date(`${startValue}T00:00:00`);
        const endDate = new Date(`${endValue}T23:59:59`);

        if (!Number.isNaN(startDate.getTime()) && !Number.isNaN(endDate.getTime())) {
            return startDate > endDate;
        }
        
        return false;
    }

    connectedCallback() {
        const sessionData = sessionStorage.getItem(SESSION_KEY);
        if (sessionData) {
            try {
                const parsedSession = JSON.parse(sessionData);
                if (parsedSession.isLoggedIn && parsedSession.userId) {
                    this.userId = parsedSession.userId;
                    this.currentScreen = 'reporting';
                    this.loadMetadataConfigs();
                    this.loadConfigPanelPreferences();
                }
            } catch (e) {
                sessionStorage.removeItem(SESSION_KEY);
            }
        }
    }

    handleUserIdChange(event) { this.userId = event.target.value; }

    handleRecoverUserIdChange(event) { this.recoverUserId = event.target.value; }

    handlePinInput(event) {
        const input = event.target;
        const index = parseInt(input.dataset.index, 10);

        let value = input.value.replace(/[^0-9]/g, '');
        if (value.length > 1) {
            value = value.slice(0, 1);
        }
        input.value = value;

        if (value.length === 1 && index < 3) {
            const nextInput = this.template.querySelector(`.pin-input[data-index="${index + 1}"]`);
            if (nextInput) {
                nextInput.removeAttribute('disabled');
                nextInput.focus();
            }
        }
    }

    handlePinKeyDown(event) {
        const input = event.target;
        const index = parseInt(input.dataset.index, 10);

        if (event.key === 'Backspace') {
            if (!input.value && index > 0) {
                const prevInput = this.template.querySelector(`.pin-input[data-index="${index - 1}"]`);
                if (prevInput) {
                    prevInput.focus();
                    prevInput.value = '';
                    input.setAttribute('disabled', 'true');
                }
            }
        }
    }

    getEnteredPin() {
        let pin = '';
        const boxes = this.template.querySelectorAll('.pin-box');
        boxes.forEach(box => { pin += box.value; });
        return pin;
    }

    async handleLogin(event) {
        if (event) event.preventDefault();

        let pinCode = '';
        const pinInputs = this.template.querySelectorAll('.pin-input');
        pinInputs.forEach(input => {
            pinCode += input.value;
        });

        if (!this.userId || pinCode.length < 4) {
            this.showToast('Error', 'Please enter your User ID and complete 4-Digit PIN.', 'error');
            return;
        }

        this.isLoggingIn = true;
        try {
            const responseStr = await verifyCredentialsAndGetGateways({ username: this.userId, password: pinCode });
            const response = JSON.parse(responseStr);

            if (response.status === 'Success') {
                sessionStorage.setItem(SESSION_KEY, JSON.stringify({ userId: this.userId, isLoggedIn: true }));
                this.selectedTile = '';
                this.currentGatewayProperName = '';
                this.currentScreen = 'reporting';
                this.loadMetadataConfigs();
                this.loadConfigPanelPreferences();
            } else {
                this.showToast('Login Failed', response.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Could not connect to Server.', 'error');
        } finally {
            this.isLoggingIn = false;
        }
    }

    handleLogout() {
        this.userId = '';
        this.currentScreen = 'login';
        sessionStorage.removeItem(SESSION_KEY);

        setTimeout(() => {
            const boxes = this.template.querySelectorAll('.pin-box');
            boxes.forEach(box => { box.value = ''; });
        }, 100);
    }

    // --- SIDEBAR NAVIGATION METHODS ---
    navigateToHome() {
        if (this.isLoggedIn) {
            this.selectedTile = '';
            this.currentGatewayProperName = '';
            this.integrationExpiryAlert = null;
            this.currentScreen = 'tiles';
        }
    }

    navigateToHomeResetContext() {
        if (this.isLoggedIn) {
            this.selectedTile = '';
            this.currentGatewayProperName = '';
            this.integrationExpiryAlert = null;
            this.currentScreen = 'tiles';
        }
    }

    navigateToDashboard() {
        if (this.isLoggedIn) {
            this.currentScreen = 'dashboard';
        }
    }

    navigateToReporting() {
        if (this.isLoggedIn) {
            this.currentScreen = 'reporting';
        }
    }

    handleSidebarBack() {
        if (this.currentScreen === 'config' || this.currentScreen === 'dashboard' || this.currentScreen === 'reporting' || this.currentScreen === 'mapping' || this.currentScreen === 'scheduler') {
            this.selectedTile = '';
            this.currentGatewayProperName = '';
            this.currentScreen = 'tiles';
        }
    }

    handleTileClick(event) {
        const clickedTileId = event.currentTarget.dataset.id;
        this.selectedTile = clickedTileId;
        this.integrationExpiryAlert = null;
        const isActiveProduct = this.isSubscribedTile(clickedTileId);

        const tileDef = this.allTilesDefinition.find(tile => tile.id === clickedTileId);
        if (tileDef) {
            this.currentGatewayProperName = tileDef.label;
        }

        this.handleIntegrationExpiryAlert(clickedTileId);

        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => ({
            ...c,
            isSelected: c.provider.toLowerCase() === this.selectedTile.toLowerCase(),
            isEditing: false
        }));
        this.currentScreen = isActiveProduct ? 'reporting' : 'config';
    }

    handleBackToTiles() {
        this.navigateToHomeResetContext();
    }

    async loadMetadataConfigs() {
        try {
            const configs = await getPaymentMetadataConfigs();

            const fieldLabels = {
                'AuthorizeNet_API_Login_ID__c': 'API Login ID',
                'AuthorizeNet_Public_Client_Key__c': 'Public Client Key',
                'AuthorizeNet_Webhook_Signing_Key__c': 'Webhook Signing Key',
                'AuthorizeNet_Active__c': 'Active',
                'AuthorizeNet_Use_Sandbox__c': 'Use Sandbox',
                'AuthorizeNet_Start_Date__c': 'Start Date',
                'AuthorizeNet_End_Date__c': 'End Date',
                'Stripe_Publishable_Key__c': 'Publishable Key',
                'Stripe_Webhook_Signing_Secret__c': 'Webhook Signing Secret',
                'Stripe_Active__c': 'Active',
                'Stripe_Use_Sandbox__c': 'Use Sandbox',
                'Stripe_Start_Date__c': 'Start Date',
                'Stripe_End_Date__c': 'End Date',
                'PayPal_ClientId__c': 'Client ID',
                'PayPal_Active__c': 'Active',
                'PayPal_UseSandbox__c': 'Use Sandbox',
                'PayPal_StartDate__c': 'Start Date',
                'PayPal_EndDate__c': 'End Date',
                'Shopify_Store_URL__c': 'Store URL',
                'Shopify_Access_Token__c': 'Access Token',
                'Shopify_API_Key__c': 'API Key',
                'Shopify_API_Secret__c': 'API Secret',
                'Shopify_Is_Active__c': 'Active',
                'Shopify_End_Date__c': 'End Date',
                'QuickBooks_Realm_ID__c': 'Realm ID',
                'QuickBooks_Is_Active__c': 'Active',
                'QuickBooks_Start_Date__c': 'Start Date',
                'QuickBooks_End_Date__c': 'End Date',
                'FedEx_Client_Id__c': 'Client ID',
                'FedEx_Client_Secret__c': 'Client Secret',
                'FedEx_Account_Number__c': 'Account Number',
                'FedEx_Environment__c': 'Environment',
                'FedEx_Default_Service_Type__c': 'Default Service Type',
                'FedEx_Default_Packaging_Type__c': 'Default Packaging Type',
                'FedEx_Default_Pickup_Type__c': 'Default Pickup Type',
                'FedEx_Active__c': 'Active',
                'FedEx_End_Date__c': 'End Date',
                'UPS_Client_Id__c': 'Client ID',
                'UPS_Client_Secret__c': 'Client Secret',
                'UPS_Account_Number__c': 'Account Number',
                'UPS_Environment__c': 'Environment',
                'UPS_Default_Service_Code__c': 'Default Service Code',
                'UPS_Active__c': 'Active',
                'UPS_End_Date__c': 'End Date'
            };

            this.paymentMetadataConfigs = (configs || []).map(config => {
                const formValues = { ...config.fields };
                return {
                    ...config,
                    isSelected: false,
                    isEditing: false,
                    formValues: formValues,
                    editableFieldsData: (config.editableFields || []).map(fieldName => {
                        const isCheckbox = fieldName.includes('Active') || fieldName.includes('Sandbox');
                        const isReadOnlyDate = fieldName.includes('Date');
                        const isTrue = formValues[fieldName] === 'true' || formValues[fieldName] === true;

                        const properLabel = fieldLabels[fieldName] || fieldName.replace('__c', '').replace(/_/g, ' ');

                        return {
                            name: fieldName,
                            label: properLabel,
                            isCheckbox: isCheckbox,
                            isReadOnly: isReadOnlyDate,
                            currentValue: isCheckbox ? isTrue : formValues[fieldName],
                            displayValue: isCheckbox ? '' : (formValues[fieldName] || ''),
                            isTrue: isTrue,
                            badgeClass: isCheckbox ? (isTrue ? 'badge-success' : 'badge-inactive') : ''
                        };
                    })
                };
            });
        } catch (error) {
            console.error(error);
        }
    }

    async loadConfigPanelPreferences() {
        try {
            const preferences = await getConfigPanelPreferences();
            this.availableProductsVisible = preferences?.availableProductsVisible !== false;
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
            const result = await updateAvailableProductsVisible({ visible: nextValue });
            if (!result || result.success !== true) {
                throw new Error(result?.message || 'Could not save Available Products preference.');
            }
            this.showToast(
                'Preference Saved',
                nextValue ? 'Available Products will be shown.' : 'Available Products will be hidden.',
                'success'
            );
        } catch (error) {
            this.availableProductsVisible = previousValue;
            this.showToast(
                'Error',
                error.body?.message || error.message || 'Could not save Available Products preference.',
                'error'
            );
        } finally {
            this.isSavingAvailableProductsPreference = false;
        }
    }

    openRenewalRequestModal() {
        this.renewalProducts = this.allTilesDefinition.map(tile => {
            const isSubscribed = this.isSubscribedTile(tile.id);
            return {
                ...tile,
                selected: false,
                isSubscribed,
                actionLabel: isSubscribed ? 'Renew existing subscription' : 'Add new subscription',
                statusLabel: isSubscribed ? 'Subscribed' : 'Not subscribed'
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
        this.renewalProducts = this.renewalProducts.map(product => (
            product.id === productId ? { ...product, selected } : product
        ));
    }

    async handleSendRenewalRequest() {
        const selectedProducts = this.renewalProducts.filter(product => product.selected);
        const renewalProductKeys = selectedProducts
            .filter(product => product.isSubscribed)
            .map(product => product.id);
        const additionalSubscriptionProductKeys = selectedProducts
            .filter(product => !product.isSubscribed)
            .map(product => product.id);

        if (!renewalProductKeys.length && !additionalSubscriptionProductKeys.length) {
            this.showToast('Select Products', 'Select at least one product to include in the request.', 'warning');
            return;
        }

        this.isSendingRenewalEmail = true;
        try {
            const result = await sendProductRenewalRequest({
                renewalProductKeys,
                additionalSubscriptionProductKeys
            });

            if (!result || result.success !== true) {
                throw new Error(result?.message || 'Could not send the renewal request.');
            }

            this.showToast('Request Sent', result.message, 'success');
            this.isRenewalModalOpen = false;
            this.renewalProducts = [];
        } catch (error) {
            this.showToast(
                'Request Failed',
                error.body?.message || error.message || 'Could not send the renewal request.',
                'error'
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
                bannerClass: `renewal-alert renewal-alert-${alert.variant || 'warning'}`
            };
            this.showToast(alert.title, alert.message, alert.variant || 'warning');
        } catch (error) {
            this.integrationExpiryAlert = {
                title: 'Expiry Check Failed',
                message: error.body?.message || error.message || 'Could not check renewal status.',
                bannerClass: 'renewal-alert renewal-alert-error'
            };
        }
    }

    toggleEditMode(event) {
        const provider = event.currentTarget.dataset.provider;
        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
            if (c.provider === provider) c.isEditing = !c.isEditing;
            return c;
        });
    }

    handleFieldChange(event) {
        const { field, provider } = event.target.dataset;
        const isCheckbox = event.target.type === 'checkbox';
        const val = isCheckbox ? event.target.checked : event.target.value;

        if (!this.metadataFormValues[provider]) this.metadataFormValues[provider] = {};
        this.metadataFormValues[provider][field] = val;

        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
            if (c.provider === provider) {
                c.editableFieldsData.forEach(f => {
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
            const fieldValues = this.metadataFormValues[provider] || {};

            const result = await updatePaymentMetadata({ provider: provider, fieldValuesJson: JSON.stringify(fieldValues) });

            if (result.success) {
                this.showToast('Success', 'Configuration saved successfully! (Deployment in background)', 'success');

                this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
                    if (c.provider === provider) {
                        c.isEditing = false;
                        c.isSelected = true;

                        const activeFieldName = Object.keys(fieldValues).find(k => k.includes('Active'));
                        if (activeFieldName) {
                            c.active = fieldValues[activeFieldName] === true || fieldValues[activeFieldName] === 'true';
                        }

                        c.editableFieldsData.forEach(f => {
                            if (fieldValues[f.name] !== undefined) {
                                const val = fieldValues[f.name];
                                f.currentValue = val;
                                f.displayValue = f.isCheckbox ? '' : (val || '');
                                f.isTrue = val === true || val === 'true';
                            }
                        });
                    }
                    return c;
                });

                this.paymentMetadataConfigs = [...this.paymentMetadataConfigs];

            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            console.error('Apex Error:', error);
            const errorMessage = error.body?.message || error.message || 'Failed to save configuration.';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleMetadataDelete(event) {
        const provider = event.currentTarget.dataset.provider;

        if (!confirm(`Are you sure you want to delete the configuration for ${provider}?`)) {
            return;
        }

        this.isSaving = true;
        try {
            const config = this.paymentMetadataConfigs.find(c => c.provider === provider);
            const fieldValues = {};

            if (config && config.editableFieldsData) {
                config.editableFieldsData.forEach(field => {
                    fieldValues[field.name] = field.isCheckbox ? false : null;
                });
            }

            const result = await updatePaymentMetadata({ provider: provider, fieldValuesJson: JSON.stringify(fieldValues) });

            if (result.success) {
                this.showToast('Deleted', `${provider} configuration deleted successfully!`, 'success');

                this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
                    if (c.provider === provider) {
                        c.active = false;
                        c.isEditing = false;
                        c.editableFieldsData.forEach(f => {
                            f.currentValue = f.isCheckbox ? false : '';
                            f.displayValue = f.isCheckbox ? 'No' : '';
                            if (f.isCheckbox) f.badgeClass = 'badge-inactive';
                        });
                    }
                    return c;
                });

                this.paymentMetadataConfigs = [...this.paymentMetadataConfigs];
                this.currentScreen = 'tiles';
            } else {
                this.showToast('Delete Failed', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to delete configuration.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    goToForgotPinScreen() {
        this.recoverUserId = this.userId;
        this.currentScreen = 'forgotPin';
    }

    handleBackToLogin() {
        this.currentScreen = 'login';
    }

    async submitPinRecovery() {
        if (!this.recoverUserId) {
            this.showToast('User ID Required', 'Please enter your User ID to reset your PIN.', 'warning');
            return;
        }

        this.isRecoveringPin = true;
        try {
            const responseStr = await recoverPin({ username: this.recoverUserId });
            const response = JSON.parse(responseStr);

            if (response.status === 'Success') {
                this.showToast('Check Your Email', 'If your User ID exists in our system, we have sent a PIN recovery email.', 'success');
                this.currentScreen = 'login';
            } else {
                this.showToast('Notice', response.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Could not connect to server for PIN recovery.', 'error');
        } finally {
            this.isRecoveringPin = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    navigateToMapping() {
        if (this.isLoggedIn) {
            this.currentScreen = 'mapping';
        }
    }

    get integrationOptions() {
        return [
            { label: 'QuickBooks Online', value: 'qbonline' }
        ];
    }
}
