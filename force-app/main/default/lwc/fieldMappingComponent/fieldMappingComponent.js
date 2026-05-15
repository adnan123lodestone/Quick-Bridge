import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSalesforceObjects from '@salesforce/apex/FieldMappingController.getSalesforceObjects';
import getObjectFields from '@salesforce/apex/FieldMappingController.getObjectFields';
import getQuickBooksFields from '@salesforce/apex/FieldMappingController.getQuickBooksFields';
import getExistingMappings from '@salesforce/apex/FieldMappingController.getExistingMappings';
import getMappingDirectionAvailability from '@salesforce/apex/FieldMappingController.getMappingDirectionAvailability';
import saveFieldMappings from '@salesforce/apex/FieldMappingController.saveFieldMappings';
import saveChildFieldMappings from '@salesforce/apex/FieldMappingController.saveChildFieldMappings';
import getDraftOrderSetting from '@salesforce/apex/FieldMappingController.getDraftOrderSetting';
import saveDraftOrderSetting from '@salesforce/apex/FieldMappingController.saveDraftOrderSetting';

export default class FieldMappingComponent extends LightningElement {
    @track selectedIntegration = 'qbonline';
    @track selectedSFObject = 'Account';
    @track selectedQBObject = 'Customer';
    @track mappingRows = [];
    @track rowCounter = 1;
    @track sfObjectOptions = [];
    @track sfFieldOptions = [];
    @track qbFieldOptions = [];
    @track isLoading = true;
    @track directionAvailability = {
        inboundAllowed: true,
        outboundAllowed: true,
        twoWayAllowed: true,
        allDirectionsBlocked: false,
        message: ''
    };
    @track syncDirectionBaseOptions = [
        { label: 'SF to QBO', value: 'SF to QBO' },
        { label: 'QBO to SF', value: 'QBO to SF' },
        { label: 'Two-Way', value: 'Two-Way' }
    ];

    @track qbObjectOptions = [
        { label: 'Customer', value: 'Customer', selected: false },
        { label: 'Vendor', value: 'Vendor', selected: false },
        { label: 'Item', value: 'Item', selected: false },
        { label: 'Invoice', value: 'Invoice', selected: false },
        { label: 'Credit Memo', value: 'CreditMemo', selected: false },
        { label: 'Purchase Order', value: 'PurchaseOrder', selected: false },
        { label: 'Tax Code', value: 'TaxCode', selected: false }
    ];

    // --- Child Mapping Variables ---
    @track childSfObject = '';
    @track childQbObject = 'InvoiceLine';
    @track childMappingRows = [];
    @track childSfFieldOptions = [];
    @track childQbFieldOptions = [];
    @track showChildMapping = false;
    @track mapDraftAsEstimate = false;

    connectedCallback() {
        this.loadInitialData();

        getDraftOrderSetting()
            .then(result => {
                this.mapDraftAsEstimate = result;
            })
            .catch(error => {
                console.error('Error loading draft order setting:', error);
            });
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
            this.sfObjectOptions = result.map((obj) => ({
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

    loadQuickBooksFields() {
        return getQuickBooksFields({
            sfObject: this.selectedSFObject,
            qbObject: this.selectedQBObject
        }).then((result) => {
            this.qbFieldOptions = (result || []).map((field) => ({
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

    updateQBObjectSelection(sfObject) {
        const objectMap = {
            Account: 'Customer',
            Contact: 'Customer',
            Product2: 'Item',
            Order: 'Invoice',
            Invoice__c: 'Invoice',
            Credit_Memo__c: 'CreditMemo',
            Purchase_Order__c: 'PurchaseOrder',
            Item_Sales_Tax__c: 'TaxCode'
        };

        let key = sfObject;
        if (sfObject && sfObject.endsWith('__c') && (sfObject.match(/__/g) || []).length === 2) {
            key = sfObject.split('__')[1] + '__c';
        }

        this.selectedQBObject = objectMap[key] || 'Customer';
        this.qbObjectOptions = this.qbObjectOptions.map((opt) => ({
            ...opt,
            selected: opt.value === this.selectedQBObject
        }));
    }

    buildMappingRows(savedMappings) {
        const requiredQbFields = this.qbFieldOptions.filter((field) => field.required);
        const rows = [];
        let counter = 1;

        requiredQbFields.forEach((field) => {
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
            const isRequired = requiredQbFields.some((field) => field.value === mapping.externalField);
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

        this.updateQBObjectSelection(objectName);
        this.sfObjectOptions = this.sfObjectOptions.map((opt) => ({
            ...opt,
            selected: opt.value === objectName
        }));

        const childObjectMap = {
            'Order': 'OrderItem',
            'QuickBridgeTLG__Invoice__c': 'QuickBridgeTLG__Invoice_Line__c',
            'Invoice__c': 'Invoice_Line__c'
        };

        if (childObjectMap[this.selectedSFObject]) {
            this.childSfObject = childObjectMap[this.selectedSFObject];
            this.showChildMapping = true;
            this.loadChildFields();
        } else {
            this.showChildMapping = false;
            this.childSfObject = '';
            this.childMappingRows = [];
        }

        Promise.all([
            this.loadObjectFields(objectName),
            this.loadQuickBooksFields(),
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

    handleQBObjectChange(event) {
        this.selectedQBObject = event.target.value;
        this.qbObjectOptions = this.qbObjectOptions.map((opt) => ({
            ...opt,
            selected: opt.value === this.selectedQBObject
        }));
        this.isLoading = true;

        Promise.all([
            this.loadQuickBooksFields(),
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
            const qbField = this.qbFieldOptions.find((option) => option.value === row.externalField);
            const qbType = qbField ? qbField.type : null;
            const availableSfOptions = qbType
                ? this.sfFieldOptions.filter((option) => this.isTypeMatch(option.type, qbType))
                : [];
            const currentSfFieldValid = row.sfField && availableSfOptions.some((option) => option.value === row.sfField);
            const selectedDirection = this.getAvailableDirectionValue(row.syncDirection, allowedDirections);

            return {
                ...row,
                sfField: currentSfFieldValid ? row.sfField : '',
                syncDirection: selectedDirection,
                isSFFieldDisabled: !row.isMandatory && !row.externalField,
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
            if (row.id !== rowId) {
                return row;
            }

            const qbField = this.qbFieldOptions.find((option) => option.value === value);
            const sfField = this.sfFieldOptions.find((option) => option.value === row.sfField);
            const keepSfField = qbField && sfField && this.isTypeMatch(sfField.type, qbField.type);

            return {
                ...row,
                externalField: value,
                sfField: value && keepSfField ? row.sfField : ''
            };
        });
        this.updateRowDropdowns();
    }

    async handleSave() {
        if (this.isMappingBlocked) {
            this.showToast('Validation Error', this.directionConflictMessage, 'error');
            return;
        }

        const duplicateExternalFields = this.getDuplicateExternalFields();
        if (duplicateExternalFields.length > 0) {
            this.showToast('Validation Error', 'Each QuickBooks field can only be mapped once.', 'error');
            return;
        }

        const missingRequiredRow = this.mappingRows.find(
            (row) => row.isMandatory && (!row.externalField || !row.sfField)
        );
        if (missingRequiredRow) {
            this.showToast('Validation Error', 'Map a Salesforce field to every required QuickBooks field.', 'error');
            return;
        }

        const rowsToSave = this.mappingRows.filter((row) => row.sfField && row.externalField).map((row) => ({
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
                this.isLoading = false;
                this.showToast('Success', result, 'success');
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', error.body?.message || error.message, 'error');
            });

        if (this.showChildMapping && this.childMappingRows.length) {
            const childRowsToSave = this.childMappingRows
                .filter(row => row.sfField && row.qbField)
                .map(row => ({
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

    handleReset() {
        this.handleSalesforceObjectChange({ target: { value: this.selectedSFObject } });
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
            if (option.value === 'QBO to SF') {
                return this.directionAvailability.inboundAllowed;
            }
            if (option.value === 'SF to QBO') {
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
        if (['CURRENCY', 'DOUBLE', 'INTEGER', 'PERCENT', 'DECIMAL', 'LONG', 'NUMBER'].includes(value)) {
            return 'NUMBER';
        }
        if (['DATE', 'DATETIME'].includes(value)) {
            return 'DATE';
        }
        if (value === 'BOOLEAN') {
            return 'BOOLEAN';
        }
        return 'STRING';
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
        return this.showChildMapping && this.selectedSFObject === 'Order';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleSyncDirectionChange(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        const value = event.target.value;
        this.mappingRows = this.mappingRows.map((row) =>
            row.id === rowId ? { ...row, syncDirection: value } : row
        );
        this.updateRowDropdowns();
    }


    loadChildFields() {
        this.childSfFieldOptions = [];
        this.childQbFieldOptions = [];
        this.childMappingRows = [];

        Promise.all([
            getObjectFields({ objectName: this.childSfObject }),
            getQuickBooksFields({ sfObject: this.childSfObject, qbObject: this.childQbObject }),
            getExistingMappings({ integration: this.selectedIntegration, sfObject: this.childSfObject })
        ])
            .then(([sfFields, qbFields, savedMappings]) => {
                this.childSfFieldOptions = (sfFields || []).map(f => ({ label: f.label, value: f.value, type: f.type }));
                this.childQbFieldOptions = (qbFields || []).map(f => ({
                    label: f.label + (f.required ? ' *' : ''),
                    value: f.value,
                    type: f.type,
                    required: f.required
                }));
                this.initializeChildRows(savedMappings || []);
            })
            .catch(error => {
                console.error('Error loading child fields:', error);
                this.showToast('Error', 'Failed to load child fields: ' + (error.body?.message || error.message), 'error');
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
        this.childQbFieldOptions.forEach(qbField => {
            if (!qbField) return;
            if (qbField.required) {
                const existing = savedMappings.find(m => m.externalField === qbField.value);
                const syncDir = existing ? this.getAvailableDirectionValue(existing.syncDirection) : this.getAvailableDirectionValue();
                rows.push({
                    id: cCounter++,
                    sfField: existing?.sfField || '',
                    qbField: qbField.value,
                    isMandatory: true,
                    isSFFieldDisabled: false,
                    syncDirection: syncDir,
                    sfFieldOptions: this.buildChildSfOptions(existing?.sfField || ''),
                    qbFieldOptions: this.buildChildQbOptions(qbField.value),
                    syncDirectionOptions: this.buildSyncDirectionOptions(syncDir)
                });
            }
        });

        // Non‑required saved mappings (additional rows)
        savedMappings.forEach(mapping => {
            const isRequired = this.childQbFieldOptions.some(f => f.required && f.value === mapping.externalField);
            if (!isRequired) {
                const syncDir = this.getAvailableDirectionValue(mapping.syncDirection);
                rows.push({
                    id: cCounter++,
                    sfField: mapping.sfField,
                    qbField: mapping.externalField,
                    isMandatory: false,
                    isSFFieldDisabled: false,
                    syncDirection: syncDir,
                    sfFieldOptions: this.buildChildSfOptions(mapping.sfField),
                    qbFieldOptions: this.buildChildQbOptions(mapping.externalField),
                    syncDirectionOptions: this.buildSyncDirectionOptions(syncDir)
                });
            }
        });

        this.childMappingRows = rows;
    }

    buildChildSfOptions(selectedValue) {
        if (!this.childSfFieldOptions || !Array.isArray(this.childSfFieldOptions)) {
            return [];
        }
        return this.childSfFieldOptions.map(opt => ({
            ...opt,
            selected: opt.value === selectedValue
        }));
    }

    buildChildQbOptions(selectedValue) {
        if (!this.childQbFieldOptions || !Array.isArray(this.childQbFieldOptions)) {
            return [];
        }
        return this.childQbFieldOptions.map(opt => ({
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
        const newId = this.childMappingRows.length > 0
            ? Math.max(...this.childMappingRows.map(r => r.id)) + 1
            : 1000;
        const defaultDir = this.getAvailableDirectionValue();

        this.childMappingRows = [...this.childMappingRows, {
            id: newId,
            sfField: '',
            qbField: '',
            isMandatory: false,
            isSFFieldDisabled: true,
            syncDirection: defaultDir,
            sfFieldOptions: this.buildChildSfOptions(''),
            qbFieldOptions: this.buildChildQbOptions(''),
            syncDirectionOptions: this.buildSyncDirectionOptions(defaultDir)
        }];
    }

    handleRemoveChildRow(event) {
        const rowId = event.currentTarget?.dataset?.rowId;
        if (!rowId) return;
        const numericRowId = Number(rowId);
        if (isNaN(numericRowId)) return;

        this.childMappingRows = this.childMappingRows.filter(row => row && row.id !== numericRowId);
    }

    handleChildSfFieldChange(event) {
        const rowId = event.currentTarget?.dataset?.rowId;
        if (!rowId) return;
        const numericRowId = Number(rowId);
        if (isNaN(numericRowId)) return;

        const value = event.target.value;

        this.childMappingRows = this.childMappingRows.map(row => {
            if (!row || row.id !== numericRowId) return row;
            return {
                ...row,
                sfField: value,
                sfFieldOptions: this.buildChildSfOptions(value)
            };
        }).filter(row => row);
    }

    handleChildQbFieldChange(event) {
        const rowId = event.currentTarget?.dataset?.rowId;
        if (!rowId) return;
        const numericRowId = Number(rowId);
        if (isNaN(numericRowId)) return;

        const value = event.target.value;

        this.childMappingRows = this.childMappingRows.map(row => {
            if (!row || row.id !== numericRowId) return row;
            const isSFFieldDisabled = !value;
            return {
                ...row,
                qbField: value,
                qbFieldOptions: this.buildChildQbOptions(value),
                isSFFieldDisabled: isSFFieldDisabled
            };
        }).filter(row => row);
    }

    handleChildSyncDirectionChange(event) {
        const rowId = event.currentTarget?.dataset?.rowId;
        if (!rowId) return;
        const numericRowId = Number(rowId);
        if (isNaN(numericRowId)) return;

        const value = event.target.value;

        this.childMappingRows = this.childMappingRows.map(row => {
            if (!row || row.id !== numericRowId) return row;
            return {
                ...row,
                syncDirection: value,
                syncDirectionOptions: this.buildSyncDirectionOptions(value)
            };
        }).filter(row => row);
    }

    handleDraftChange(event) {
        this.mapDraftAsEstimate = event.target.checked;
        saveDraftOrderSetting({ value: this.mapDraftAsEstimate })
            .catch(error => {
                this.showToast('Error', 'Failed to save setting: ' + (error.body?.message || error.message), 'error');
                // Revert checkbox if save fails
                this.mapDraftAsEstimate = !event.target.checked;
            });
    }
}