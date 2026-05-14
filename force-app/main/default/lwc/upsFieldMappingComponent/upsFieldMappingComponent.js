import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSalesforceObjects from '@salesforce/apex/FieldMappingController.getSalesforceObjects';
import getObjectFields from '@salesforce/apex/FieldMappingController.getObjectFields';
import getUPSFields from '@salesforce/apex/FieldMappingController.getUPSFields';
import getExistingUPSMappings from '@salesforce/apex/FieldMappingController.getExistingUPSMappings';
import saveUPSFieldMappings from '@salesforce/apex/FieldMappingController.saveUPSFieldMappings';

const ACTIONS = [
    {
        value: 'validateAddress',
        label: 'Validate Address',
        scope: 'Any object',
        note: 'Uses SF fields to validate an address via UPS, shows the correction to the user, and only writes the selected validated address when the user confirms.'
    },
    {
        value: 'getRateQuote',
        label: 'Get Rate Quote',
        scope: 'Any object',
        note: 'Builds a rate request from mapped fields, shows every returned UPS service option, and stores the user-selected response fields.'
    },
    {
        value: 'createShipment',
        label: 'Create Shipment',
        scope: 'Shipment-centric',
        note: 'Creates or uses a shipment record, updates package, label, tracking, cost, and status fields after UPS confirms.'
    },
    {
        value: 'generateLabel',
        label: 'Generate Label',
        scope: 'Shipment only',
        note: 'Stores the generated label as a Salesforce File and maps label metadata back to the shipment.'
    },
    {
        value: 'syncTrackingStatus',
        label: 'Sync Tracking Status',
        scope: 'Shipment plus schedule',
        note: 'Uses tracking number, updates latest shipment status, inserts deduped tracking events, and stops terminal shipments. Also captures tracking numbers and exception fields automatically.'
    },
    {
        value: 'createReturnLabel',
        label: 'Create Return Label',
        scope: 'Shipment, return, case, RMA',
        note: 'Creates a separate return shipment, preserving the original shipment and storing return tracking plus label file data.'
    },
    {
        value: 'voidShipment',
        label: 'Void Shipment',
        scope: 'Shipment only',
        note: 'Calls UPS void/cancel before updating Salesforce and is blocked for delivered or terminal shipments.'
    }
];

export default class UpsFieldMappingComponent extends LightningElement {
    @track selectedAction = 'validateAddress';
    @track selectedDirection = 'SF to UPS';
    @track selectedSFObject = 'Case';
    @track sfObjectOptions = [];
    @track sfFieldOptions = [];
    @track upsFieldOptions = [];
    @track mappingRows = [];
    @track rowCounter = 1;
    @track isLoading = true;

    directionOptions = [
        { label: 'SF to UPS', value: 'SF to UPS' },
        { label: 'UPS to SF', value: 'UPS to SF' }
    ];

    get actionOptions() {
        return ACTIONS.map((action) => ({
            ...action,
            selected: action.value === this.selectedAction,
            className: action.value === this.selectedAction ? 'action-tile selected' : 'action-tile'
        }));
    }

    get selectedActionConfig() {
        return ACTIONS.find((action) => action.value === this.selectedAction) || ACTIONS[0];
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
        return this.selectedAction === 'handleDeliveryExceptions';
    }

    connectedCallback() {
        this.loadInitialData();
    }

    loadInitialData() {
        this.isLoading = true;
        this.loadSalesforceObjects()
            .then(() => this.reloadMappings())
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }

    loadSalesforceObjects() {
        return getSalesforceObjects().then((result) => {
            const preferredObjects = [
                'Case',
                'Shipment',
                'Carrier_Shipment__c',
                'Carrier_Package__c',
                'Carrier_Rate_Quote__c',
                'ReturnOrder',
                'Account',
                'Order'
            ];
            const filtered = (result || []).filter((obj) => preferredObjects.includes(obj.value));
            const optionsSource = filtered.length ? filtered : (result || []);
            this.sfObjectOptions = optionsSource.map((obj) => ({
                label: obj.label,
                value: obj.value,
                selected: obj.value === this.selectedSFObject
            }));
            if (!this.sfObjectOptions.some((obj) => obj.value === this.selectedSFObject) && this.sfObjectOptions.length) {
                this.selectedSFObject = this.sfObjectOptions[0].value;
                this.sfObjectOptions[0].selected = true;
            }
        });
    }

    reloadMappings() {
        this.isLoading = true;
        return Promise.all([
            getObjectFields({ objectName: this.selectedSFObject }),
            getUPSFields({ actionName: this.selectedAction, direction: this.selectedDirection }),
            getExistingUPSMappings({ actionName: this.selectedAction, sfObject: this.selectedSFObject })
        ])
            .then(([sfFields, upsFields, savedMappings]) => {
                this.sfFieldOptions = (sfFields || []).map((field) => ({
                    ...field,
                    type: this.normalizeType(field.type)
                }));
                this.upsFieldOptions = (upsFields || []).map((field) => ({
                    ...field,
                    type: this.normalizeType(field.type),
                    required: Boolean(field.required)
                }));
                this.buildMappingRows(savedMappings || []);
                this.isLoading = false;
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }

    buildMappingRows(savedMappings) {
        const relevantSavedMappings = savedMappings.filter((mapping) => {
            const direction = mapping.syncDirection || 'SF to UPS';
            return direction === this.selectedDirection;
        });
        const requiredUPSFields = this.upsFieldOptions.filter((field) => field.required);
        const rows = [];
        let counter = 1;

        requiredUPSFields.forEach((field) => {
            const existingMapping = relevantSavedMappings.find((mapping) => mapping.externalField === field.value);
            rows.push({
                id: counter++,
                sfField: existingMapping?.sfField || '',
                externalField: field.value,
                syncDirection: this.selectedDirection,
                isMandatory: true
            });
        });

        relevantSavedMappings.forEach((mapping) => {
            const isRequired = requiredUPSFields.some((field) => field.value === mapping.externalField);
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
                sfField: '',
                externalField: '',
                syncDirection: this.selectedDirection,
                isMandatory: false
            });
        }

        this.mappingRows = rows;
        this.rowCounter = counter;
        this.updateRowDropdowns();
    }

    handleActionSelect(event) {
        this.selectedAction = event.currentTarget.dataset.action;
        this.selectedDirection = this.selectedAction === 'handleDeliveryExceptions' ? 'UPS to SF' : this.selectedDirection;
        this.reloadMappings();
    }

    handleDirectionChange(event) {
        this.selectedDirection = event.target.value;
        this.reloadMappings();
    }

    handleSalesforceObjectChange(event) {
        this.selectedSFObject = event.target.value;
        this.sfObjectOptions = this.sfObjectOptions.map((option) => ({
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
                sfField: '',
                externalField: '',
                syncDirection: this.selectedDirection,
                isMandatory: false
            }
        ];
        this.updateRowDropdowns();
    }

    handleRemoveRow(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        this.mappingRows = this.mappingRows.filter((row) => row.id !== rowId);
        if (!this.mappingRows.length) {
            this.handleAddRow();
            return;
        }
        this.updateRowDropdowns();
    }

    handleExternalFieldChange(event) {
        const rowId = Number(event.currentTarget.dataset.rowId);
        const value = event.target.value;
        this.mappingRows = this.mappingRows.map((row) => {
            if (row.id !== rowId) return row;
            const upsField = this.upsFieldOptions.find((option) => option.value === value);
            const sfField = this.sfFieldOptions.find((option) => option.value === row.sfField);
            const keepSfField = upsField && sfField && this.isTypeMatch(sfField.type, upsField.type);
            return {
                ...row,
                externalField: value,
                sfField: keepSfField ? row.sfField : ''
            };
        });
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

    handleSave() {
        const duplicateExternalFields = this.getDuplicateExternalFields();
        if (duplicateExternalFields.length) {
            this.showToast('Validation Error', 'Each UPS field can only be mapped once per direction.', 'error');
            return;
        }

        const missingRequiredRow = this.mappingRows.find((row) => row.isMandatory && (!row.externalField || !row.sfField));
        if (missingRequiredRow) {
            this.showToast('Validation Error', 'Map a Salesforce field to every required UPS field.', 'error');
            return;
        }

        const rowsToSave = this.mappingRows
            .filter((row) => row.sfField && row.externalField)
            .map((row) => ({
                sfField: row.sfField,
                externalField: row.externalField,
                syncDirection: this.selectedDirection
            }));

        this.isLoading = true;
        saveUPSFieldMappings({
            actionName: this.selectedAction,
            sfObject: this.selectedSFObject,
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
        this.reloadMappings();
    }

    updateRowDropdowns() {
        this.mappingRows = this.mappingRows.map((row) => {
            const upsField = this.upsFieldOptions.find((option) => option.value === row.externalField);
            const upsType = upsField ? upsField.type : null;
            const availableSfOptions = upsType
                ? this.sfFieldOptions.filter((option) => this.isTypeMatch(option.type, upsType))
                : this.sfFieldOptions;
            const currentSfFieldValid = row.sfField && availableSfOptions.some((option) => option.value === row.sfField);

            return {
                ...row,
                sfField: currentSfFieldValid ? row.sfField : '',
                isSFFieldDisabled: !row.isMandatory && !row.externalField,
                externalFieldOptions: this.upsFieldOptions.map((option) => ({
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

    normalizeType(type) {
        const value = (type || '').toUpperCase();
        if (['CURRENCY', 'DOUBLE', 'INTEGER', 'PERCENT', 'DECIMAL', 'LONG', 'NUMBER'].includes(value)) return 'NUMBER';
        if (['DATE', 'DATETIME'].includes(value)) return 'DATE';
        if (value === 'BOOLEAN') return 'BOOLEAN';
        return 'STRING';
    }

    isTypeMatch(sfType, upsType) {
        if (!sfType || !upsType) return true;
        return this.normalizeType(sfType) === this.normalizeType(upsType);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}