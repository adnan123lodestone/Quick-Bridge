import { LightningElement, track } from 'lwc';
import getOrderFields from '@salesforce/apex/FieldMappingController.getOrderFields';
import getSalesforceObjects from '@salesforce/apex/FieldMappingController.getSalesforceObjects';
import getObjectFields from '@salesforce/apex/FieldMappingController.getObjectFields';
import getQuickBooksFields from '@salesforce/apex/FieldMappingController.getQuickBooksFields';

const QUICKBOOKS_FIELDS = [
    { label: 'QB - Order ID', value: 'qb_order_id' },
    { label: 'QB - Customer ID', value: 'qb_customer_id' },
    { label: 'QB - Amount', value: 'qb_amount' },
    { label: 'QB - Status', value: 'qb_status' },
    { label: 'QB - Date', value: 'qb_date' },
    { label: 'QB - Line Items', value: 'qb_line_items' },
    { label: 'QB - Billing Address', value: 'qb_billing_addr' },
    { label: 'QB - Shipping Address', value: 'qb_shipping_addr' },
    { label: 'QB - Memo', value: 'qb_memo' },
    { label: 'QB - Department', value: 'qb_department' },
    { label: 'QB - Tax Total', value: 'qb_tax_total' },
    { label: 'QB - Due Date', value: 'qb_due_date' }
];

const KLAVIYO_FIELDS = [
    { label: 'Klaviyo - Profile ID', value: 'kl_profile_id' },
    { label: 'Klaviyo - Email', value: 'kl_email' },
    { label: 'Klaviyo - Phone Number', value: 'kl_phone' },
    { label: 'Klaviyo - First Name', value: 'kl_first_name' },
    { label: 'Klaviyo - Last Name', value: 'kl_last_name' },
    { label: 'Klaviyo - City', value: 'kl_city' },
    { label: 'Klaviyo - State', value: 'kl_state' },
    { label: 'Klaviyo - Country', value: 'kl_country' },
    { label: 'Klaviyo - Postal Code', value: 'kl_postal_code' },
    { label: 'Klaviyo - Custom Property', value: 'kl_custom_property' },
    { label: 'Klaviyo - Event', value: 'kl_event' }
];

export default class FieldMappingComponent extends LightningElement {
    @track selectedIntegration = 'qbonline';
    @track selectedSFObject = 'Order';
    @track mappingRows = [{ id: 1, sfField: '', externalField: '', isLastRow: true }];
    @track rowCounter = 2;
    @track sfObjectOptions = [];
    @track sfFieldOptions = [];
    @track qbFieldOptions = [];
    @track klaviyoFieldOptions = [];
    @track isLoading = true;
    @track errorMessage = '';

    connectedCallback() {
        this.loadInitialData();
    }

    loadInitialData() {
        Promise.all([
            this.loadSalesforceObjects(),
            this.loadQuickBooksFields(),
            this.loadKlaviyoFields()
        ])
            .then(() => {
                // Load Order fields by default
                return this.loadObjectFields('Order');
            })
            .then(() => {
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error loading data: ' + (error.body?.message || error.message);
                this.isLoading = false;
                console.error('Error:', error);
            });
    }

    loadSalesforceObjects() {
        return new Promise((resolve, reject) => {
            getSalesforceObjects()
                .then(result => {
                    this.sfObjectOptions = result.map(obj => ({
                        label: obj.label,
                        value: obj.value
                    }));
                    resolve();
                })
                .catch(error => reject(error));
        });
    }

    loadObjectFields(objectName) {
        return new Promise((resolve, reject) => {
            if (!objectName) {
                this.sfFieldOptions = [];
                resolve();
                return;
            }

            getObjectFields({ objectName: objectName })
                .then(result => {
                    this.sfFieldOptions = result.map(field => ({
                        label: field.label,
                        value: field.value
                    }));
                    resolve();
                })
                .catch(error => reject(error));
        });
    }

    loadQuickBooksFields() {
        return new Promise((resolve) => {
            getQuickBooksFields()
                .then(result => {
                    this.qbFieldOptions = result.map(field => ({
                        label: field.label,
                        value: field.value
                    }));
                    resolve();
                })
                .catch(error => {
                    console.error('Error loading QB fields:', error);
                    // Don't reject, just log
                    resolve();
                });
        });
    }

    loadKlaviyoFields() {
        return new Promise((resolve) => {
            // For Klaviyo fields, you can either:
            // 1. Add an Apex method getKlaviyoFields() similar to getQuickBooksFields()
            // 2. Use hardcoded fields
            // For now, using hardcoded Klaviyo fields
            this.klaviyoFieldOptions = [
                { label: 'Klaviyo - Profile ID', value: 'kl_profile_id' },
                { label: 'Klaviyo - Email', value: 'kl_email' },
                { label: 'Klaviyo - Phone Number', value: 'kl_phone' },
                { label: 'Klaviyo - First Name', value: 'kl_first_name' },
                { label: 'Klaviyo - Last Name', value: 'kl_last_name' },
                { label: 'Klaviyo - City', value: 'kl_city' },
                { label: 'Klaviyo - State', value: 'kl_state' },
                { label: 'Klaviyo - Country', value: 'kl_country' },
                { label: 'Klaviyo - Postal Code', value: 'kl_postal_code' },
                { label: 'Klaviyo - Custom Property', value: 'kl_custom_property' },
                { label: 'Klaviyo - Event', value: 'kl_event' }
            ];
            resolve();
        });
    }

    get isQBOnlineSelected() {
        return this.selectedIntegration === 'qbonline';
    }

    get isKlaviyoSelected() {
        return this.selectedIntegration === 'klaviyo';
    }

    get externalFieldOptions() {
        return this.selectedIntegration === 'qbonline' ? this.qbFieldOptions : this.klaviyoFieldOptions;
    }

    handleIntegrationChange(event) {
        this.selectedIntegration = event.detail.value;
    }

    handleSalesforceObjectChange(event) {
        const objectName = event.detail.value;
        this.selectedSFObject = objectName;
        this.isLoading = true;
        
        this.loadObjectFields(objectName)
            .then(() => {
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error loading object fields: ' + (error.body?.message || error.message);
                this.isLoading = false;
                console.error('Error:', error);
            });
    }

    handleAddRow() {
        // Mark previous last row as not last
        this.mappingRows = this.mappingRows.map(row => ({
            ...row,
            isLastRow: false
        }));

        // Add new row as last row
        this.mappingRows = [
            ...this.mappingRows,
            { id: this.rowCounter, sfField: '', externalField: '', isLastRow: true }
        ];
        this.rowCounter++;
    }

    handleRemoveRow(event) {
        const rowId = event.currentTarget.dataset.rowId;
        this.mappingRows = this.mappingRows.filter(row => row.id !== parseInt(rowId));
        
        // Update isLastRow for remaining rows
        if (this.mappingRows.length > 0) {
            this.mappingRows = this.mappingRows.map((row, index) => ({
                ...row,
                isLastRow: index === this.mappingRows.length - 1
            }));
        }
    }

    handleSFFieldChange(event) {
        const rowId = parseInt(event.currentTarget.dataset.rowId);
        const value = event.detail.value;
        const rowIndex = this.mappingRows.findIndex(row => row.id === rowId);
        if (rowIndex !== -1) {
            this.mappingRows[rowIndex].sfField = value;
            this.mappingRows = [...this.mappingRows];
        }
    }

    handleExternalFieldChange(event) {
        const rowId = parseInt(event.currentTarget.dataset.rowId);
        const value = event.detail.value;
        const rowIndex = this.mappingRows.findIndex(row => row.id === rowId);
        if (rowIndex !== -1) {
            this.mappingRows[rowIndex].externalField = value;
            this.mappingRows = [...this.mappingRows];
        }
    }

    handleSave() {
        // Validate that all fields are filled
        const isValid = this.mappingRows.every(row => row.sfField && row.externalField);
        
        if (!isValid) {
            alert('Please fill all fields before saving');
            return;
        }

        const mappingData = {
            integration: this.selectedIntegration,
            fields: this.mappingRows
        };

        console.log('Saving mapping:', JSON.stringify(mappingData));
        alert('Mappings saved successfully!');
    }

    handleReset() {
        this.selectedIntegration = 'qbonline';
        this.selectedSFObject = 'Order';
        this.mappingRows = [{ id: 1, sfField: '', externalField: '', isLastRow: true }];
        this.rowCounter = 2;
        
        // Reload Order fields
        this.isLoading = true;
        this.loadObjectFields('Order')
            .then(() => {
                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = 'Error loading fields: ' + (error.body?.message || error.message);
                this.isLoading = false;
            });
    }
}