import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getGatewayMappingConfig from '@salesforce/apex/PaymentInvoiceMappingController.getGatewayMappingConfig';
import getEligibleSourceObjects from '@salesforce/apex/PaymentInvoiceMappingController.getEligibleSourceObjects';
import getCreateableObjects from '@salesforce/apex/PaymentInvoiceMappingController.getCreateableObjects';
import getObjectsWithLookupTo from '@salesforce/apex/PaymentInvoiceMappingController.getObjectsWithLookupTo';
import getObjectFields from '@salesforce/apex/PaymentInvoiceMappingController.getObjectFields';
import getLookupFields from '@salesforce/apex/PaymentInvoiceMappingController.getLookupFields';
import getInvoiceRequestFields from '@salesforce/apex/PaymentInvoiceMappingController.getInvoiceRequestFields';
import getGatewayTransactionFields from '@salesforce/apex/PaymentInvoiceMappingController.getGatewayTransactionFields';
import saveGatewayMappingConfig from '@salesforce/apex/PaymentInvoiceMappingController.saveGatewayMappingConfig';

const DEFAULT_SOURCE_OBJECT = 'Order';
const DEFAULT_INVOICE_OBJECT = 'Invoice__c';
const DEFAULT_TRANSACTION_OBJECT = 'Portal_Payment_Transaction__c';
const SOURCE_REQUIRED_ROWS = [
    { sourceField: '', targetField: 'amount', targetLabel: 'Amount', requiredSide: 'target' }
];
const INVOICE_REQUIRED_ROWS = [
    { sourceField: 'amount', targetField: 'Amount__c', sourceLabel: 'Amount' },
    { sourceField: 'hostedInvoiceUrl', targetField: 'Stripe_Invoice_Link__c', sourceLabel: 'Stripe Hosted Invoice URL' },
    { sourceField: 'referenceNumber', targetField: 'Reference_number__c', sourceLabel: 'Reference Number' },
    { sourceField: 'status', targetField: 'Status__c', sourceLabel: 'Status' },
    { sourceField: 'invoiceDate', targetField: 'Invoice_Date__c', sourceLabel: 'Invoice Date' },
    { sourceField: 'stripeInvoiceId', targetField: 'Stripe_Invoice_Id__c', sourceLabel: 'Stripe Invoice Id' },
    { sourceField: 'customerEmail', targetField: '', sourceLabel: 'Customer Email', isOptional: true },
    { sourceField: 'paymentQrCode', targetField: '', sourceLabel: 'Payment QR Code (HTML)', isOptional: true }
];
const TRANSACTION_REQUIRED_ROWS = [
    { sourceField: 'gatewayEventId', targetField: 'Gateway_Event_Id__c', sourceLabel: 'Gateway Event Id' },
    { sourceField: 'gatewayEventType', targetField: 'Gateway_Event_Type__c', sourceLabel: 'Gateway Event Type' },
    { sourceField: 'gatewayAmount', targetField: 'Gateway_Amount__c', sourceLabel: 'Gateway Amount' },
    { sourceField: 'gatewayReferenceNumber', targetField: 'Gateway_Reference_Number__c', sourceLabel: 'Gateway Reference Number' },
    { sourceField: 'gatewayTransactionId', targetField: 'Gateway_Transaction_Id__c', sourceLabel: 'Gateway Transaction Id' },
    { sourceField: 'paymentType', targetField: 'Payment_Type__c', sourceLabel: 'Payment Type' },
    { sourceField: 'stripeLiveMode', targetField: 'Stripe_Live_Mode__c', sourceLabel: 'Stripe Live Mode' }
];
const INVOICE_RECORD_SOURCE_OPTIONS = [
    { label: 'Amount', value: 'amount' },
    { label: 'Stripe Hosted Invoice URL', value: 'hostedInvoiceUrl' },
    { label: 'Reference Number', value: 'referenceNumber' },
    { label: 'Status', value: 'status' },
    { label: 'Invoice Date', value: 'invoiceDate' },
    { label: 'Due Date', value: 'dueDate' },
    { label: 'Customer Email', value: 'customerEmail' },
    { label: 'Stripe Invoice Id', value: 'stripeInvoiceId' },
    { label: 'Payment QR Code (HTML)', value: 'paymentQrCode' }
];

export default class InvoiceMappingTool extends LightningElement {
    @api gateway = 'stripe';

    @track config = this.emptyConfig();
    @track sourceObjectOptions = [];
    @track targetObjectOptions = [];
    @track invoiceObjectOptions = [];
    @track transactionObjectOptions = [];
    @track customerLookupOptions = [];
    @track sourceFieldOptions = [];
    @track invoiceLookupOptions = [];
    @track invoiceFieldOptions = [];
    @track transactionLookupOptions = [];
    @track transactionFieldOptions = [];
    @track invoiceRequestFieldOptions = [];
    @track gatewayTransactionFieldOptions = [];
    @track isLoading = false;
    @track isSaving = false;
    @track sourceRows = [];
    @track invoiceRows = [];
    @track transactionRows = [];
    @track openSections = {
        source: true,
        invoice: false,
        transaction: false
    };

    useCustomSource = false;
    useCustomInvoice = false;
    useCustomTransaction = false;
    defaultSourceObject = DEFAULT_SOURCE_OBJECT;
    defaultInvoiceObject = DEFAULT_INVOICE_OBJECT;
    defaultTransactionObject = DEFAULT_TRANSACTION_OBJECT;

    connectedCallback() {
        this.loadInitialState();
    }

    get gatewayLabel() {
        return this.gateway === 'stripe' ? 'Stripe' : this.gateway;
    }

    get sourceObjectValue() {
        return this.config.sourceObject;
    }

    get invoiceObjectValue() {
        return this.config.invoiceObject;
    }

    get transactionObjectValue() {
        return this.config.transactionObject;
    }

    get isSourceObjectDisabled() {
        return !this.useCustomSource;
    }

    get isInvoiceObjectDisabled() {
        return !this.useCustomInvoice;
    }

    get isTransactionObjectDisabled() {
        return !this.useCustomTransaction;
    }

    get isBusy() {
        return this.isLoading || this.isSaving;
    }

    get saveDisabled() {
        return this.isBusy ||
            !this.config.sourceObject ||
            !this.config.sourceCustomerLookupField ||
            !this.config.invoiceObject ||
            !this.config.invoiceSourceLookupField ||
            !this.config.transactionObject ||
            !this.config.transactionSourceLookupField ||
            this.hasIncompleteRows(this.sourceRows) ||
            this.hasIncompleteRows(this.invoiceRows) ||
            this.hasIncompleteRows(this.transactionRows);
    }

    get standardSourceChecked() {
        return !this.useCustomSource;
    }

    get standardInvoiceChecked() {
        return !this.useCustomInvoice;
    }

    get standardTransactionChecked() {
        return !this.useCustomTransaction;
    }

    get invoiceRecordSourceFieldOptions() {
        return INVOICE_RECORD_SOURCE_OPTIONS;
    }

    get sourceRowsWithOptions() {
        return (this.sourceRows || []).map((row) => ({ ...row, filteredSourceOptions: this.sourceFieldOptions }));
    }

    get invoiceRowsWithOptions() {
        return (this.invoiceRows || []).map((row) => ({
            ...row,
            filteredTargetOptions: this.invoiceFieldOptions,
            isPinned: row.isRequired || row.isOptional
        }));
    }

    get transactionRowsWithOptions() {
        return (this.transactionRows || []).map((row) => ({ ...row, filteredTargetOptions: this.transactionFieldOptions }));
    }

    get sourceObjectUiOptions() {
        if (this.useCustomSource) return this.sourceObjectOptions;
        return [
            { label: 'Order (Order)', value: this.defaultSourceObject },
            ...(this.sourceObjectOptions || [])
        ];
    }

    get hasNoCustomInvoiceObjects() {
        return this.useCustomInvoice && this.config.sourceObject && this.invoiceObjectOptions.length === 0;
    }

    get hasNoCustomTransactionObjects() {
        return this.useCustomTransaction && this.config.sourceObject && this.transactionObjectOptions.length === 0;
    }

    get isSourceComplete() {
        return Boolean(
            this.config.sourceObject &&
            this.config.sourceCustomerLookupField &&
            this.requiredRowsComplete(this.sourceRows) &&
            !this.hasIncompleteRows(this.sourceRows)
        );
    }

    get isInvoiceLocked() {
        return !this.isSourceComplete;
    }

    get isTransactionLocked() {
        return !this.isSourceComplete;
    }

    get showSourceBody() {
        return this.openSections.source;
    }

    get showInvoiceBody() {
        return this.openSections.invoice && !this.isInvoiceLocked;
    }

    get showTransactionBody() {
        return this.openSections.transaction && !this.isTransactionLocked;
    }

    get sourceToggleIcon() {
        return this.showSourceBody ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get invoiceToggleIcon() {
        return this.showInvoiceBody ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get transactionToggleIcon() {
        return this.showTransactionBody ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get invoiceSectionClass() {
        return this.isInvoiceLocked ? 'mapping-section section-locked' : 'mapping-section';
    }

    get transactionSectionClass() {
        return this.isTransactionLocked ? 'mapping-section section-locked' : 'mapping-section';
    }

    emptyConfig() {
        return {
            gateway: this.gateway || 'stripe',
            sourceObject: DEFAULT_SOURCE_OBJECT,
            sourceCustomerLookupField: '',
            sourceCustomerTargetObject: '',
            sourceEmailField: '',
            invoiceObject: DEFAULT_INVOICE_OBJECT,
            invoiceSourceLookupField: '',
            transactionObject: DEFAULT_TRANSACTION_OBJECT,
            transactionSourceLookupField: '',
            sourceMappings: [],
            invoiceMappings: [],
            transactionMappings: []
        };
    }

    async loadInitialState() {
        this.isLoading = true;
        try {
            const [
                savedConfig,
                sourceObjects,
                targetObjects,
                invoiceRequestFields,
                gatewayTransactionFields
            ] = await Promise.all([
                getGatewayMappingConfig({ gateway: this.gateway }),
                getEligibleSourceObjects(),
                getCreateableObjects(),
                getInvoiceRequestFields(),
                getGatewayTransactionFields({ gateway: this.gateway })
            ]);

            this.config = { ...this.emptyConfig(), ...(savedConfig || {}) };
            this.sourceObjectOptions = sourceObjects || [];
            this.targetObjectOptions = targetObjects || [];
            this.defaultSourceObject = DEFAULT_SOURCE_OBJECT;
            this.defaultInvoiceObject = this.findDefaultObjectValue(this.targetObjectOptions, DEFAULT_INVOICE_OBJECT, '__Invoice__c');
            this.defaultTransactionObject = this.findDefaultObjectValue(this.targetObjectOptions, DEFAULT_TRANSACTION_OBJECT, '__Portal_Payment_Transaction__c');
            this.useCustomSource = !this.isDefaultSourceObject(this.config.sourceObject);
            this.useCustomInvoice = !this.isDefaultInvoiceObject(this.config.invoiceObject);
            this.useCustomTransaction = !this.isDefaultTransactionObject(this.config.transactionObject);
            this.invoiceRequestFieldOptions = invoiceRequestFields || [];
            this.gatewayTransactionFieldOptions = gatewayTransactionFields || [];
            this.sourceRows = this.withClientIds(this.config.sourceMappings);
            this.invoiceRows = this.withClientIds(this.config.invoiceMappings);
            this.transactionRows = this.withClientIds(this.config.transactionMappings);
            this.applyRequiredRows();

            await this.refreshDependentOptions();
            if (this.isSourceComplete) {
                this.openSections = { ...this.openSections, invoice: true };
            } else {
                this.syncLockedSections();
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error, 'Failed to load invoice mapping setup.'), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async refreshDependentOptions() {
        await this.refreshSourceOptions();
        await this.refreshTargetObjectOptions();
        await this.refreshInvoiceOptions();
        await this.refreshTransactionOptions();
    }

    async refreshSourceOptions() {
        if (!this.config.sourceObject) return;
        const [sourceFields, customerLookups] = await Promise.all([
            getObjectFields({ objectApiName: this.config.sourceObject }),
            getLookupFields({ objectApiName: this.config.sourceObject, targetObjectApiName: null })
        ]);
        this.sourceFieldOptions = sourceFields || [];
        this.customerLookupOptions = customerLookups || [];
    }

    async refreshTargetObjectOptions() {
        if (!this.config.sourceObject) {
            this.invoiceObjectOptions = [];
            this.transactionObjectOptions = [];
            return;
        }

        const objectsWithLookup = await getObjectsWithLookupTo({ targetObjectApiName: this.config.sourceObject });
        const options = objectsWithLookup || [];
        this.invoiceObjectOptions = options;
        this.transactionObjectOptions = options;

        if (this.useCustomInvoice && this.config.invoiceObject && !this.hasOption(this.invoiceObjectOptions, this.config.invoiceObject)) {
            this.config = { ...this.config, invoiceObject: '', invoiceSourceLookupField: '' };
            this.invoiceLookupOptions = [];
            this.invoiceFieldOptions = [];
        }
        if (this.useCustomTransaction && this.config.transactionObject && !this.hasOption(this.transactionObjectOptions, this.config.transactionObject)) {
            this.config = { ...this.config, transactionObject: '', transactionSourceLookupField: '' };
            this.transactionLookupOptions = [];
            this.transactionFieldOptions = [];
        }
    }

    async refreshInvoiceOptions() {
        if (!this.config.invoiceObject || !this.config.sourceObject) return;
        const [invoiceFields, invoiceLookups] = await Promise.all([
            getObjectFields({ objectApiName: this.config.invoiceObject }),
            getLookupFields({ objectApiName: this.config.invoiceObject, targetObjectApiName: this.config.sourceObject })
        ]);
        this.invoiceFieldOptions = invoiceFields || [];
        this.invoiceLookupOptions = invoiceLookups || [];
        this.invoiceRows = this.normalizeRequiredTargets(this.invoiceRows, INVOICE_REQUIRED_ROWS, this.invoiceFieldOptions, this.useCustomInvoice);
        if (!this.config.invoiceSourceLookupField && this.invoiceLookupOptions.length === 1) {
            this.config = { ...this.config, invoiceSourceLookupField: this.invoiceLookupOptions[0].value };
        }
    }

    async refreshTransactionOptions() {
        if (!this.config.transactionObject || !this.config.sourceObject) return;
        const [transactionFields, transactionLookups] = await Promise.all([
            getObjectFields({ objectApiName: this.config.transactionObject }),
            getLookupFields({ objectApiName: this.config.transactionObject, targetObjectApiName: this.config.sourceObject })
        ]);
        this.transactionFieldOptions = transactionFields || [];
        this.transactionLookupOptions = transactionLookups || [];
        this.transactionRows = this.normalizeRequiredTargets(this.transactionRows, TRANSACTION_REQUIRED_ROWS, this.transactionFieldOptions, this.useCustomTransaction);
        if (!this.config.transactionSourceLookupField && this.transactionLookupOptions.length === 1) {
            this.config = { ...this.config, transactionSourceLookupField: this.transactionLookupOptions[0].value };
        }
    }

    handleToggleSection(event) {
        const section = event.currentTarget.dataset.section;
        if ((section === 'invoice' || section === 'transaction') && !this.isSourceComplete) {
            this.showSourceLockToast();
            this.syncLockedSections();
            return;
        }

        this.openSections = {
            ...this.openSections,
            [section]: !this.openSections[section]
        };
    }

    async handleSourceModeChange(event) {
        this.useCustomSource = !event.target.checked;
        this.config = {
            ...this.config,
            sourceObject: this.useCustomSource ? '' : this.defaultSourceObject,
            sourceCustomerLookupField: '',
            sourceCustomerTargetObject: '',
            sourceEmailField: '',
            invoiceSourceLookupField: '',
            transactionSourceLookupField: ''
        };
        this.customerLookupOptions = [];
        this.invoiceLookupOptions = [];
        this.transactionLookupOptions = [];
        if (this.config.sourceObject) {
            await this.refreshDependentOptions();
        }
        this.syncLockedSections();
    }

    async handleInvoiceModeChange(event) {
        if (this.isInvoiceLocked) {
            this.showSourceLockToast();
            return;
        }
        this.useCustomInvoice = !event.target.checked;
        this.config = {
            ...this.config,
            invoiceObject: this.useCustomInvoice ? '' : this.defaultInvoiceObject,
            invoiceSourceLookupField: ''
        };
        this.invoiceLookupOptions = [];
        this.invoiceFieldOptions = [];
        if (this.useCustomInvoice) {
            await this.refreshTargetObjectOptions();
        }
        if (this.config.invoiceObject) {
            await this.refreshInvoiceOptions();
        }
    }

    async handleTransactionModeChange(event) {
        if (this.isTransactionLocked) {
            this.showSourceLockToast();
            return;
        }
        this.useCustomTransaction = !event.target.checked;
        this.config = {
            ...this.config,
            transactionObject: this.useCustomTransaction ? '' : this.defaultTransactionObject,
            transactionSourceLookupField: ''
        };
        this.transactionLookupOptions = [];
        this.transactionFieldOptions = [];
        if (this.useCustomTransaction) {
            await this.refreshTargetObjectOptions();
        }
        if (this.config.transactionObject) {
            await this.refreshTransactionOptions();
        }
    }

    async handleSourceObjectChange(event) {
        this.config = {
            ...this.config,
            sourceObject: event.detail.value,
            sourceCustomerLookupField: '',
            sourceCustomerTargetObject: '',
            invoiceSourceLookupField: '',
            transactionSourceLookupField: ''
        };
        this.config = {
            ...this.config,
            invoiceObject: this.useCustomInvoice ? '' : this.defaultInvoiceObject,
            transactionObject: this.useCustomTransaction ? '' : this.defaultTransactionObject
        };
        await this.refreshDependentOptions();
        this.syncLockedSections();
    }

    handleCustomerLookupChange(event) {
        const selected = this.customerLookupOptions.find((option) => option.value === event.detail.value);
        this.config = {
            ...this.config,
            sourceCustomerLookupField: event.detail.value,
            sourceCustomerTargetObject: selected?.referenceTo || ''
        };
        this.syncLockedSections();
    }

    async handleInvoiceObjectChange(event) {
        if (this.isInvoiceLocked) {
            this.showSourceLockToast();
            return;
        }
        this.config = {
            ...this.config,
            invoiceObject: event.detail.value,
            invoiceSourceLookupField: ''
        };
        await this.refreshInvoiceOptions();
    }

    handleInvoiceLookupChange(event) {
        if (this.isInvoiceLocked) {
            this.showSourceLockToast();
            return;
        }
        this.config = { ...this.config, invoiceSourceLookupField: event.detail.value };
    }

    async handleTransactionObjectChange(event) {
        if (this.isTransactionLocked) {
            this.showSourceLockToast();
            return;
        }
        this.config = {
            ...this.config,
            transactionObject: event.detail.value,
            transactionSourceLookupField: ''
        };
        await this.refreshTransactionOptions();
    }

    handleTransactionLookupChange(event) {
        if (this.isTransactionLocked) {
            this.showSourceLockToast();
            return;
        }
        this.config = { ...this.config, transactionSourceLookupField: event.detail.value };
    }

    addSourceRow() {
        this.sourceRows = [...this.sourceRows, this.newRow(false, 'source')];
        this.syncLockedSections();
    }

    addInvoiceRow() {
        if (this.isInvoiceLocked) {
            this.showSourceLockToast();
            return;
        }
        this.invoiceRows = [...this.invoiceRows, this.newRow(false, 'invoice')];
    }

    addTransactionRow() {
        if (this.isTransactionLocked) {
            this.showSourceLockToast();
            return;
        }
        this.transactionRows = [...this.transactionRows, this.newRow(false, 'transaction')];
    }

    removeSourceRow(event) {
        this.sourceRows = this.removeRow(this.sourceRows, event.currentTarget.dataset.id, 'source');
        this.syncLockedSections();
    }

    removeInvoiceRow(event) {
        if (this.isInvoiceLocked) {
            this.showSourceLockToast();
            return;
        }
        this.invoiceRows = this.removeRow(this.invoiceRows, event.currentTarget.dataset.id, 'invoice');
    }

    removeTransactionRow(event) {
        if (this.isTransactionLocked) {
            this.showSourceLockToast();
            return;
        }
        this.transactionRows = this.removeRow(this.transactionRows, event.currentTarget.dataset.id, 'transaction');
    }

    handleSourceRowChange(event) {
        this.sourceRows = this.updateRow(this.sourceRows, event);
        this.syncLockedSections();
    }

    handleInvoiceRowChange(event) {
        if (this.isInvoiceLocked) {
            this.showSourceLockToast();
            return;
        }
        this.invoiceRows = this.updateRow(this.invoiceRows, event);
    }

    handleTransactionRowChange(event) {
        if (this.isTransactionLocked) {
            this.showSourceLockToast();
            return;
        }
        this.transactionRows = this.updateRow(this.transactionRows, event);
    }

    async handleSave() {
        const duplicateMessage =
            this.findDuplicateMessage(this.sourceRows, 'source invoice request') ||
            this.findDuplicateMessage(this.invoiceRows, 'invoice record') ||
            this.findDuplicateMessage(this.transactionRows, 'payment transaction');

        if (duplicateMessage) {
            this.showToast('Duplicate Mapping', duplicateMessage, 'error');
            return;
        }

        this.isSaving = true;
        try {
            const payload = {
                ...this.config,
                gateway: this.gateway,
                sourceMappings: this.cleanRows(this.sourceRows),
                invoiceMappings: this.cleanRows(this.invoiceRows),
                transactionMappings: this.cleanRows(this.transactionRows)
            };
            const message = await saveGatewayMappingConfig({ configJson: JSON.stringify(payload) });
            this.showToast('Success', message || 'Stripe invoice mappings saved.', 'success');
        } catch (error) {
            this.showToast('Save Failed', this.getErrorMessage(error, 'Could not save Stripe invoice mappings.'), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    withClientIds(rows = []) {
        return (rows || []).map((row) => ({ ...row, id: row.developerName || this.rowId(), isRequired: row.isRequired === true }));
    }

    newRow(isRequired = false, sectionName = '') {
        return { id: this.rowId(), sourceField: '', targetField: '', isRequired, sectionName };
    }

    rowId() {
        return String(Date.now()) + '-' + String(Math.random()).slice(2);
    }

    updateRow(rows, event) {
        const id = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        return rows.map((row) => {
            if (row.id !== id) return row;
            if (field === 'sourceField' && row.lockSource) return row;
            if (field === 'targetField' && row.lockTarget) return row;
            return { ...row, [field]: value };
        });
    }

    removeRow(rows, id, sectionName) {
        const row = rows.find((candidate) => candidate.id === id);
        if (row?.isRequired || row?.isOptional) return rows;
        const filtered = rows.filter((row) => row.id !== id);
        return filtered.length ? filtered : [this.newRow(false, sectionName)];
    }

    cleanRows(rows) {
        return (rows || [])
            .filter((row) => row.sourceField && row.targetField)
            .map((row) => ({
                sourceField: row.sourceField,
                targetField: row.targetField,
                isRequired: row.isRequired === true
            }));
    }

    hasIncompleteRows(rows) {
        return (rows || []).some((row) => {
            if (row.isOptional) return false;
            return (row.sourceField && !row.targetField) || (!row.sourceField && row.targetField);
        });
    }

    requiredRowsComplete(rows) {
        return (rows || [])
            .filter((row) => row.isRequired)
            .every((row) => row.sourceField && row.targetField);
    }

    syncLockedSections() {
        if (this.isSourceComplete) return;
        this.openSections = {
            ...this.openSections,
            invoice: false,
            transaction: false
        };
    }

    showSourceLockToast() {
        this.showToast(
            'Complete Source Setup',
            'Complete the source object, customer lookup, and required invoice request mapping before configuring invoice or payment transaction objects.',
            'warning'
        );
    }

    findDuplicateMessage(rows, label) {
        const sources = new Set();
        const targets = new Set();
        for (const row of rows || []) {
            if (!row.sourceField || !row.targetField) continue;
            if (sources.has(row.sourceField)) return `Each ${label} source field can only be mapped once.`;
            if (targets.has(row.targetField)) return `Each ${label} target field can only be mapped once.`;
            sources.add(row.sourceField);
            targets.add(row.targetField);
        }
        return '';
    }

    isDefaultSourceObject(objectApiName) {
        return objectApiName === DEFAULT_SOURCE_OBJECT;
    }

    isDefaultInvoiceObject(objectApiName) {
        return objectApiName === DEFAULT_INVOICE_OBJECT || (objectApiName || '').endsWith('__Invoice__c');
    }

    isDefaultTransactionObject(objectApiName) {
        return objectApiName === DEFAULT_TRANSACTION_OBJECT || (objectApiName || '').endsWith('__Portal_Payment_Transaction__c');
    }

    findDefaultObjectValue(options, plainName, namespacedSuffix) {
        const direct = (options || []).find((option) => option.value === plainName);
        if (direct) return direct.value;
        const namespaced = (options || []).find((option) => (option.value || '').endsWith(namespacedSuffix));
        return namespaced?.value || plainName;
    }

    applyRequiredRows() {
        this.sourceRows = this.mergeRequiredRows(this.sourceRows, SOURCE_REQUIRED_ROWS, 'source');
        this.invoiceRows = this.mergeRequiredRows(this.invoiceRows, INVOICE_REQUIRED_ROWS, 'invoice');
        this.transactionRows = this.mergeRequiredRows(this.transactionRows, TRANSACTION_REQUIRED_ROWS, 'transaction');
    }

    mergeRequiredRows(existingRows, requiredDefinitions, sectionName) {
        const rows = [...(existingRows || [])];
        const merged = [];

        requiredDefinitions.forEach((definition) => {
            const isOptional = definition.isOptional === true;
            const savedRow = rows.find((row) => {
                if (definition.requiredSide === 'target') return row.targetField === definition.targetField;
                return row.sourceField === definition.sourceField;
            });
            if (savedRow) {
                merged.push({
                    ...savedRow,
                    id: savedRow.id || this.rowId(),
                    isRequired: !isOptional,
                    isOptional,
                    requiredSide: definition.requiredSide || 'source',
                    lockSource: definition.requiredSide !== 'target',
                    lockTarget: definition.requiredSide === 'target',
                    sourceLabel: definition.sourceLabel,
                    targetLabel: definition.targetLabel,
                    sourceField: definition.requiredSide === 'target' ? savedRow.sourceField : definition.sourceField,
                    targetField: this.resolveDefaultField(savedRow.targetField || definition.targetField)
                });
            } else {
                merged.push({
                    id: this.rowId(),
                    sourceField: definition.sourceField,
                    targetField: this.resolveDefaultField(definition.targetField),
                    isRequired: !isOptional,
                    isOptional,
                    sectionName,
                    requiredSide: definition.requiredSide || 'source',
                    lockSource: definition.requiredSide !== 'target',
                    lockTarget: definition.requiredSide === 'target',
                    sourceLabel: definition.sourceLabel,
                    targetLabel: definition.targetLabel
                });
            }
        });

        rows.forEach((row) => {
            const isRequiredDuplicate = requiredDefinitions.some((definition) => {
                if (definition.requiredSide === 'target') return row.targetField === definition.targetField;
                return row.sourceField === definition.sourceField;
            });
            if (!isRequiredDuplicate) {
                merged.push({ ...row, id: row.id || this.rowId(), isRequired: false, sectionName });
            }
        });

        return merged;
    }

    normalizeRequiredTargets(rows, definitions, options, isCustomObject) {
        return (rows || []).map((row) => {
            if (!row.isRequired || row.lockTarget) return row;
            const definition = definitions.find((candidate) => candidate.sourceField === row.sourceField);
            if (!definition) return row;
            const resolvedField = this.resolveFieldFromOptions(row.targetField || definition.targetField, options);
            if (resolvedField) {
                return { ...row, targetField: resolvedField };
            }
            if (isCustomObject) {
                return { ...row, targetField: '' };
            }
            return row;
        });
    }

    resolveDefaultField(fieldName) {
        if (!fieldName) return fieldName;
        const options = [
            ...(this.invoiceFieldOptions || []),
            ...(this.transactionFieldOptions || [])
        ];
        const direct = options.find((option) => option.value === fieldName);
        if (direct) return direct.value;
        const namespaced = options.find((option) => (option.value || '').endsWith('__' + fieldName));
        return namespaced?.value || fieldName;
    }

    resolveFieldFromOptions(fieldName, options) {
        if (!fieldName) return '';
        const direct = (options || []).find((option) => option.value === fieldName);
        if (direct) return direct.value;
        const namespaced = (options || []).find((option) => (option.value || '').endsWith('__' + fieldName));
        return namespaced?.value || '';
    }

    hasOption(options, value) {
        return (options || []).some((option) => option.value === value);
    }

    getErrorMessage(error, fallback) {
        if (error?.body?.message) return error.body.message;
        if (Array.isArray(error?.body) && error.body.length) {
            return error.body.map((item) => item.message).filter(Boolean).join(' ');
        }
        return error?.message || fallback;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}