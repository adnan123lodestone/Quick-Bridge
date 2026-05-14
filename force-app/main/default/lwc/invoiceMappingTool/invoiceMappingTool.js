import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableObjects from '@salesforce/apex/InvoiceMappingController.getAvailableObjects';
import getObjectFields from '@salesforce/apex/InvoiceMappingController.getObjectFields';
import saveMappings from '@salesforce/apex/InvoiceMappingController.saveMappings';
import deleteMappingRecord from '@salesforce/apex/InvoiceMappingController.deleteMappingRecord';
import getAllActiveMappings from '@salesforce/apex/InvoiceMappingController.getAllActiveMappings'; 
import deactivateAllMappings from '@salesforce/apex/InvoiceMappingController.deactivateAllMappings';
import getRequiredSourceFields from '@salesforce/apex/InvoiceMappingController.getRequiredSourceFields';

export default class InvoiceMappingTool extends LightningElement {
    @track objectOptions = [];
    @track sourceFieldOptions = []; 
    @track targetFieldOptions = []; 
    @track requiredSourceFields = []; 
    @track mappingRows = []; 
    
    @track useCustomInvoice = false;
    selectedObject = '';
    isLoading = false;

    @wire(getAvailableObjects)
    wiredObjects({ error, data }) {
        if (data) {
            this.objectOptions = data;
        } else if (error) {
            this.showToast('Error', 'Failed to load objects', 'error');
        }
    }

    connectedCallback() {
        this.isLoading = true;
        getRequiredSourceFields()
            .then(reqFields => {
                this.requiredSourceFields = reqFields;
                return this.loadFields('Invoice__c', 'source');
            })
            .then(() => {
                return getAllActiveMappings();
            })
            .then(result => {
                if (result && result.length > 0) {
                    this.useCustomInvoice = true;
                    this.selectedObject = result[0].Target_Object_API_Name__c;
                    
                    this.buildMappingRows(result);
                    
                    return this.loadFields(this.selectedObject, 'target');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load initial data', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    buildMappingRows(existingMappings = []) {
        this.mappingRows = [];
        let existingMap = new Map();
        
        existingMappings.forEach(record => {
            existingMap.set(record.Source_Field_API_Name__c, record);
        });

        if (this.requiredSourceFields && this.requiredSourceFields.length > 0) {
            this.requiredSourceFields.forEach(reqField => {
                let savedRecord = existingMap.get(reqField.value);
                this.mappingRows.push({
                    id: savedRecord ? savedRecord.DeveloperName : 'Req_' + reqField.value,
                    developerName: savedRecord ? savedRecord.DeveloperName : null,
                    sourceField: reqField.value,
                    targetField: savedRecord ? savedRecord.Target_Field_API_Name__c : '',
                    isRequired: true 
                });
                if (savedRecord) existingMap.delete(reqField.value); 
            });
        }

        existingMap.forEach(record => {
            this.mappingRows.push({
                id: record.DeveloperName,
                developerName: record.DeveloperName,
                sourceField: record.Source_Field_API_Name__c,
                targetField: record.Target_Field_API_Name__c,
                isRequired: false 
            });
        });
        
        if(this.mappingRows.length === 0) {
            this.handleAddRow();
        }
    }

    async handleToggleMode(event) {
        const isChecked = event.target.checked;
        if (!isChecked) {
            const confirmed = confirm('Switching to Standard mode will deactivate all custom mappings. Proceed?');
            if (confirmed) {
                this.isLoading = true;
                try {
                    await deactivateAllMappings();
                    this.useCustomInvoice = false;
                    this.selectedObject = '';
                    this.mappingRows = [];
                    this.showToast('Success', 'Mappings deactivated.', 'success');
                } catch (error) {
                    this.showToast('Error', 'Failed to deactivate', 'error');
                    event.target.checked = true;
                } finally {
                    this.isLoading = false;
                }
            } else {
                event.target.checked = true;
            }
        } else {
            this.useCustomInvoice = true;
        }
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.loadFields(this.selectedObject, 'target').then(() => {
            this.buildMappingRows([]); 
        });
    }

    loadFields(objectName, type) {
        this.isLoading = true;
        return getObjectFields({ objectApiName: objectName })
            .then(result => {
                if(type === 'source') {
                    this.sourceFieldOptions = result;
                } else {
                    this.targetFieldOptions = result;
                }
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleAddRow() {
        this.mappingRows.push({
            id: Date.now().toString(),
            developerName: null, 
            sourceField: '',
            targetField: '',
            isRequired: false 
        });
    }

    handleRemoveRow(event) {
        const rowId = event.target.dataset.id;
        const rowToDelete = this.mappingRows.find(row => row.id === rowId);

        if(rowToDelete.isRequired) return; 

        this.mappingRows = this.mappingRows.filter(row => row.id !== rowId);

        if (rowToDelete && rowToDelete.developerName) {
            this.isLoading = true;
            deleteMappingRecord({ developerName: rowToDelete.developerName })
                .then(() => {
                    this.showToast('Deleted', 'Field mapping removed.', 'success');
                })
                .catch(() => {
                    this.showToast('Error', 'Failed to delete mapping.', 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    handleRowChange(event) {
        const rowId = event.target.dataset.id;
        const fieldName = event.target.name;
        const value = event.detail.value;

        const rowIndex = this.mappingRows.findIndex(row => row.id === rowId);
        if(rowIndex !== -1) {
            this.mappingRows[rowIndex] = { ...this.mappingRows[rowIndex], [fieldName]: value };
            this.mappingRows = [...this.mappingRows];
        }
    }

    get isSaveDisabled() {
        return this.mappingRows.length === 0 || this.mappingRows.some(row => !row.sourceField || !row.targetField);
    }

    handleSave() {
        let sourceFieldsSet = new Set();
        let targetFieldsSet = new Set();
        let hasDuplicates = false;

        for (let row of this.mappingRows) {
            if (sourceFieldsSet.has(row.sourceField) || targetFieldsSet.has(row.targetField)) {
                hasDuplicates = true;
                break;
            }
            sourceFieldsSet.add(row.sourceField);
            targetFieldsSet.add(row.targetField);
        }

        if (hasDuplicates) {
            this.showToast('Error', 'Duplicate mapping found! Each field can only be mapped once.', 'error');
            return; 
        }

        this.isLoading = true;
        
        const mappingsToSave = this.mappingRows.map((row) => {
            let cleanObj = this.selectedObject.replace('__c', '').replace(/[^a-zA-Z0-9]/g, '');
            let cleanTargetField = row.targetField.replace('__c', '').replace(/[^a-zA-Z0-9]/g, '');
            let uniqueName = ('Map_' + cleanObj + '_' + cleanTargetField).substring(0, 40);
            
            row.developerName = uniqueName;
            row.id = uniqueName;

            return {
                developerName: uniqueName,
                label: 'Mapping for ' + cleanTargetField,
                targetObject: this.selectedObject,
                sourceField: row.sourceField,
                targetField: row.targetField
            };
        });

        saveMappings({ mappingsToSave: mappingsToSave })
            .then(result => {
                this.showToast('Success', 'Mapping saved successfully!', 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : 'Error saving mapping', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}