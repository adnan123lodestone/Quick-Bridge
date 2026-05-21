import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecentWorkItems from '@salesforce/apex/IntegrationWorkAdminController.getRecentWorkItems';
import retryNow from '@salesforce/apex/IntegrationWorkAdminController.retryNow';
import cancel from '@salesforce/apex/IntegrationWorkAdminController.cancel';

const COLUMNS = [
    { label: 'Work Item', fieldName: 'Name' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Integration', fieldName: 'Integration__c' },
    { label: 'Operation', fieldName: 'Operation__c' },
    { label: 'Lock Key', fieldName: 'Lock_Key__c' },
    { label: 'Attempts', fieldName: 'Attempt_Count__c', type: 'number' },
    { label: 'Next Attempt', fieldName: 'Next_Attempt_At__c', type: 'date' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Retry Now', name: 'retry' },
                { label: 'Cancel', name: 'cancel' },
                { label: 'View Error', name: 'error' }
            ]
        }
    }
];

export default class IntegrationWorkAdmin extends LightningElement {
    @track rows = [];
    @track selectedStatus = 'All';
    @track isLoading = false;
    columns = COLUMNS;

    statusOptions = [
        { label: 'All', value: 'All' },
        { label: 'Pending', value: 'Pending' },
        { label: 'Processing', value: 'Processing' },
        { label: 'Retry', value: 'Retry' },
        { label: 'Failed', value: 'Failed' },
        { label: 'Cancelled', value: 'Cancelled' }
    ];

    connectedCallback() {
        this.loadRows();
    }

    async loadRows() {
        this.isLoading = true;
        try {
            this.rows = await getRecentWorkItems({ statusFilter: this.selectedStatus, limitSize: 100 });
        } catch (error) {
            this.toast('Error', error?.body?.message || error.message || 'Unable to load work items.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.loadRows();
    }

    handleRefresh() {
        this.loadRows();
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'error') {
            this.toast('Last Error', row.Last_Error__c || 'No error recorded.', 'info');
            return;
        }

        this.isLoading = true;
        try {
            const result = actionName === 'cancel'
                ? await cancel({ workItemId: row.Id })
                : await retryNow({ workItemId: row.Id });
            this.toast(result.success ? 'Success' : 'Notice', result.message, result.success ? 'success' : 'warning');
            await this.loadRows();
        } catch (error) {
            this.toast('Action Failed', error?.body?.message || error.message || 'Work item action failed.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}