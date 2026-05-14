import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSalesforceObjects from '@salesforce/apex/FieldMappingController.getSalesforceObjects';
import getObjectFields from '@salesforce/apex/FieldMappingController.getObjectFields';
import getShopifyFields from '@salesforce/apex/FieldMappingController.getShopifyFields';
import getExistingMappings from '@salesforce/apex/FieldMappingController.getExistingMappings';
import getMappingDirectionAvailability from '@salesforce/apex/FieldMappingController.getMappingDirectionAvailability';
import saveFieldMappings from '@salesforce/apex/FieldMappingController.saveFieldMappings';

export default class ShopifyFieldMappingComponent extends LightningElement {
    @track selectedIntegration = 'shopify';
    @track selectedSFObject = 'Account';
    @track selectedShopifyObject = 'Customer';
    @track mappingRows = [];
    @track rowCounter = 1;
    @track sfObjectOptions = [];
    @track sfFieldOptions = [];
    @track shopifyFieldOptions = [];
    @track isLoading = true;
    @track directionAvailability = {
        inboundAllowed: true,
        outboundAllowed: true,
        twoWayAllowed: true,
        allDirectionsBlocked: false,
        message: ''
    };

    @track syncDirectionBaseOptions = [
        { label: 'SF to Shopify', value: 'SF to Shopify' },
        { label: 'Shopify to SF', value: 'Shopify to SF' },
        { label: 'Two-Way',       value: 'Two-Way' }
    ];

    @track shopifyObjectOptions = [
        { label: 'Customer',  value: 'Customer',  selected: true  },
        { label: 'Order',     value: 'Order',     selected: false },
        { label: 'Product',   value: 'Product',   selected: false },
        { label: 'Line Item', value: 'LineItem',  selected: false }
    ];

    // Only expose the SF objects relevant for Shopify
    shopifyAllowedSFObjects = ['Account', 'Order', 'Product2', 'OrderItem'];

    connectedCallback() {
        this.loadInitialData();
    }

    loadInitialData() {
        this.loadSalesforceObjects()
            .then(() => this.handleSalesforceObjectChange({ target: { value: this.selectedSFObject } }))
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }

    loadSalesforceObjects() {
        return getSalesforceObjects().then((result) => {
            // Filter to only Shopify-supported objects
            const filtered = result.filter(obj => this.shopifyAllowedSFObjects.includes(obj.value));
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
                message: result?.message || '',
                otherIntegrationLabel: result?.otherIntegrationLabel || '',
                inboundConflictDirection: result?.inboundConflictDirection || '',
                outboundConflictDirection: result?.outboundConflictDirection || ''
            };
        });
    }

    updateShopifyObjectSelection(sfObject) {
        const objectMap = {
            Account:   'Customer',
            Order:     'Order',
            Product2:  'Product',
            OrderItem: 'LineItem'
        };
        this.selectedShopifyObject = objectMap[sfObject] || 'Customer';
        this.shopifyObjectOptions = this.shopifyObjectOptions.map((opt) => ({
            ...opt,
            selected: opt.value === this.selectedShopifyObject
        }));
    }

    buildMappingRows(savedMappings) {
        const requiredFields = this.shopifyFieldOptions.filter((field) => field.required);
        const rows = [];
        let counter = 1;

        requiredFields.forEach((field) => {
            const existingMapping = savedMappings.find((mapping) => mapping.externalField === field.value);
            rows.push({
                id: counter++,
                sfField: existingMapping?.sfField || '',
                externalField: field.value,
                syncDirection: this.getAvailableDirectionValue(existingMapping?.syncDirection),
                isMandatory: true
            });
        });

        savedMappings.forEach((mapping) => {
            const isRequired = requiredFields.some((field) => field.value === mapping.externalField);
            if (!isRequired) {
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
                sfField: '',
                externalField: '',
                syncDirection: this.getDefaultSyncDirection(),
                isMandatory: false
            });
        }

        this.mappingRows = rows;
        this.rowCounter = counter;
        this.updateRowDropdowns();
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

        Promise.all([
            this.loadObjectFields(objectName),
            this.loadShopifyFields(),
            this.loadDirectionAvailability(objectName),
            getExistingMappings({ integration: this.selectedIntegration, sfObject: objectName })
        ])
            .then(([, , , savedMappings]) => {
                this.buildMappingRows(savedMappings || []);
                this.isLoading = false;
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message, 'error');
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

        Promise.all([
            this.loadShopifyFields(),
            this.loadDirectionAvailability(this.selectedSFObject),
            getExistingMappings({ integration: this.selectedIntegration, sfObject: this.selectedSFObject })
        ])
            .then(([, , savedMappings]) => {
                this.buildMappingRows(savedMappings || []);
                this.isLoading = false;
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }

    updateRowDropdowns() {
        const allowedDirections = this.getAllowedSyncDirectionOptions();
        this.mappingRows = this.mappingRows.map((row) => {
            const shopifyField = this.shopifyFieldOptions.find((option) => option.value === row.externalField);
            const shopifyType = shopifyField ? shopifyField.type : null;
            const availableSfOptions = shopifyType
                ? this.sfFieldOptions.filter((option) => this.isTypeMatch(option.type, shopifyType))
                : this.sfFieldOptions;
            const currentSfFieldValid = row.sfField && availableSfOptions.some((option) => option.value === row.sfField);
            const selectedDirection = this.getAvailableDirectionValue(row.syncDirection, allowedDirections);

            return {
                ...row,
                sfField: currentSfFieldValid ? row.sfField : '',
                syncDirection: selectedDirection,
                isSFFieldDisabled: !row.isMandatory && !row.externalField,
                externalFieldOptions: this.shopifyFieldOptions.map((option) => ({
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
                sfField: '',
                externalField: '',
                syncDirection: this.getDefaultSyncDirection(),
                isMandatory: false
            }
        ];
        this.updateRowDropdowns();
    }

    handleRemoveRow(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        this.mappingRows = this.mappingRows.filter((row) => row.id !== rowId);
        if (this.mappingRows.length === 0) {
            this.handleAddRow();
            return;
        }
        this.updateRowDropdowns();
    }

    handleSFFieldChange(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        const value = event.target.value;
        this.mappingRows = this.mappingRows.map((row) =>
            row.id === rowId ? { ...row, sfField: value } : row
        );
        this.updateRowDropdowns();
    }

    handleExternalFieldChange(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        const value = event.target.value;

        this.mappingRows = this.mappingRows.map((row) => {
            if (row.id !== rowId) return row;
            const shopifyField = this.shopifyFieldOptions.find((option) => option.value === value);
            const sfField = this.sfFieldOptions.find((option) => option.value === row.sfField);
            const keepSfField = shopifyField && sfField && this.isTypeMatch(sfField.type, shopifyField.type);
            return {
                ...row,
                externalField: value,
                sfField: value && keepSfField ? row.sfField : ''
            };
        });
        this.updateRowDropdowns();
    }

    handleSyncDirectionChange(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        const value = event.target.value;
        this.mappingRows = this.mappingRows.map((row) =>
            row.id === rowId ? { ...row, syncDirection: value } : row
        );
        this.updateRowDropdowns();
    }

    handleSave() {
        if (this.isMappingBlocked) {
            this.showToast('Validation Error', this.directionConflictMessage, 'error');
            return;
        }

        const duplicateExternalFields = this.getDuplicateExternalFields();
        if (duplicateExternalFields.length > 0) {
            this.showToast('Validation Error', 'Each Shopify field can only be mapped once.', 'error');
            return;
        }

        const missingRequiredRow = this.mappingRows.find(
            (row) => row.isMandatory && (!row.externalField || !row.sfField)
        );
        if (missingRequiredRow) {
            this.showToast('Validation Error', 'Map a Salesforce field to every required Shopify field.', 'error');
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
            qbObject: this.selectedShopifyObject,
            mappingsJson: JSON.stringify(rowsToSave)
        })
            .then((result) => {
                this.isLoading = false;
                this.showToast('Success', result, 'success');
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', error.body?.message || error.message, 'error');
            });
    }

    handleReset() {
        this.handleSalesforceObjectChange({ target: { value: this.selectedSFObject } });
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
        return this.directionAvailability?.allDirectionsBlocked === true;
    }

    get directionConflictMessage() {
        return this.directionAvailability?.message || '';
    }

    getAllowedSyncDirectionOptions() {
        const allowed = this.syncDirectionBaseOptions.filter((option) => {
            if (option.value === 'Two-Way') {
                return this.directionAvailability.twoWayAllowed;
            }
            if (option.value === 'Shopify to SF') {
                return this.directionAvailability.inboundAllowed;
            }
            if (option.value === 'SF to Shopify') {
                return this.directionAvailability.outboundAllowed;
            }
            return true;
        });
        return allowed.length > 0 ? allowed : [{ label: 'No available direction', value: '' }];
    }

    getDefaultSyncDirection() {
        const allowedDirections = this.getAllowedSyncDirectionOptions();
        const twoWay = allowedDirections.find((option) => option.value === 'Two-Way');
        return twoWay ? twoWay.value : allowedDirections[0]?.value || '';
    }

    getAvailableDirectionValue(value, allowedDirections = this.getAllowedSyncDirectionOptions()) {
        const currentValue = value || this.getDefaultSyncDirection();
        return allowedDirections.some((option) => option.value === currentValue)
            ? currentValue
            : this.getDefaultSyncDirection();
    }

    normalizeType(type) {
        const value = (type || '').toUpperCase();
        if (['CURRENCY', 'DOUBLE', 'INTEGER', 'PERCENT', 'DECIMAL', 'LONG', 'NUMBER'].includes(value)) return 'NUMBER';
        if (['DATE', 'DATETIME'].includes(value)) return 'DATE';
        if (value === 'BOOLEAN') return 'BOOLEAN';
        return 'STRING';
    }

    isTypeMatch(sfType, shopifyType) {
        if (!shopifyType || !sfType) return true; // permissive for Shopify — types aren't strictly enforced
        return this.normalizeType(sfType) === this.normalizeType(shopifyType);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}