import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex'; // 💡 Refresh data dynamically
import getDynamicLogs from '@salesforce/apex/ErrorLogUtility.getDynamicLogs';

export default class ErrorLogTable extends LightningElement {
    @api gatewayName;
    @track columns = [];
    @track allErrorLogs = [];
    @track paginatedLogs = [];
    @track isRefreshing = false;
    
    // Pagination Variables
    @track currentPage = 1;
    @track pageSize = 10;
    @track totalRecords = 0;
    @track totalPages = 0;

    wiredLogsResult; // To hold wire result for refresh feature

    @wire(getDynamicLogs, { gatewayName: '$gatewayName' })
    wiredLogs(result) {
        this.wiredLogsResult = result;
        const { error, data } = result;
        
        if (data) {
            let tempCols = [...data.columns];
            
            // Remove 'Name' if admin added it in field set to avoid duplicates
            tempCols = tempCols.filter(col => col.fieldName !== 'Name' && col.fieldName !== 'QuickBridgeTLG__Name');

            // 💡 Standard Salesforce Behavior: First column is the clickable Record Name/Number
            let nameColumn = {
                label: 'Error Log Number',
                fieldName: 'recordUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'Name' },
                    target: '_blank'
                },
                initialWidth: 160
            };
            
            this.columns = [nameColumn, ...tempCols];
            
            let processedData = data.records.map(record => {
                let newRec = { ...record };
                let mobileFields = []; 
                
                // URL for the Log Number column
                newRec.recordUrl = `/lightning/r/${newRec.Id}/view`;
                
                data.columns.forEach(col => {
                    if (col.type === 'url') {
                        let originalField = col.fieldName.replace('_Url', ''); 
                        if (newRec[originalField]) {
                            newRec[col.fieldName] = `/lightning/r/${newRec[originalField]}/view`;
                            let relationName = originalField.endsWith('__c') ? originalField.replace('__c', '__r') : originalField.replace('Id', '');
                            newRec[originalField + '_Name'] = (newRec[relationName] && newRec[relationName].Name) ? newRec[relationName].Name : newRec[originalField];
                        } else {
                            newRec[col.fieldName] = '';
                            newRec[originalField + '_Name'] = '';
                        }
                    }
                    
                    if(col.fieldName !== 'Name' && col.fieldName !== 'QuickBridgeTLG__Name') {
                        let isUrl = col.type === 'url';
                        let isDate = col.type === 'date';
                        let displayValue = isUrl ? newRec[col.fieldName.replace('_Url', '') + '_Name'] : newRec[col.fieldName];
                        
                        mobileFields.push({
                            label: col.label,
                            value: displayValue,
                            isDate: isDate,
                            isUrl: isUrl && newRec[col.fieldName] !== '', 
                            urlLink: newRec[col.fieldName],
                            urlLabel: displayValue
                        });
                    }
                });
                
                newRec.mobileFields = mobileFields;
                return newRec;
            });
            
            this.allErrorLogs = processedData;
            this.totalRecords = this.allErrorLogs.length;
            this.totalPages = Math.ceil(this.totalRecords / this.pageSize);
            this.updatePagination();
            this.isRefreshing = false; // Stop spinner/refresh state
            
        } else if (error) {
            console.error('Error fetching dynamic logs:', error);
            this.isRefreshing = false;
        }
    }

    // --- REFRESH LOGIC --- //
    handleRefresh() {
        this.isRefreshing = true; // Spinner Start
        
        refreshApex(this.wiredLogsResult)
            .then(() => {
                console.log('Logs refreshed successfully');
            })
            .catch(error => {
                console.error('Error refreshing logs:', error);
            })
            .finally(() => {
                this.isRefreshing = false; 
            });
    }

    // --- PAGINATION LOGIC --- //
    updatePagination() {
        let start = (this.currentPage - 1) * this.pageSize;
        let end = this.currentPage * this.pageSize;
        this.paginatedLogs = this.allErrorLogs.slice(start, end);
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.updatePagination();
        }
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.updatePagination();
        }
    }

    get isFirstPage() { return this.currentPage === 1; }
    get isLastPage() { return this.currentPage === this.totalPages || this.totalPages === 0; }
    get hasRecords() { return this.totalRecords > 0; }
}
// import { LightningElement, api, wire } from 'lwc';
// import getRecentErrorLogs from '@salesforce/apex/PaymentGatewayService.getRecentErrorLogs';

// const COLUMNS = [
//     {
//         label: 'Date',
//         fieldName: 'CreatedDate',
//         type: 'date',
//         typeAttributes: {
//             month: 'short',
//             day: '2-digit',
//             hour: '2-digit',
//             minute: '2-digit'
//         },
//         initialWidth: 180
//     },
//     {
//         label: 'Error Message',
//         fieldName: 'Error_Message__c',
//         type: 'text',
//         wrapText: true
//     },
//     {
//         label: 'Method Name',
//         fieldName: 'Class_Method_Name__c',
//         type: 'text'
//     }
// ];

// export default class ErrorLogTable extends LightningElement {
//     @api gatewayName;
//     errorLogs;
//     columns = COLUMNS;

//     @wire(getRecentErrorLogs, { gatewayName: '$gatewayName' })
//     wiredLogs({ error, data }) {
//         if (data) {
//             this.errorLogs = data;
//         } else if (error) {
//             console.error('Error fetching logs:', error);
//         }
//     }
// }