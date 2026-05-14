import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import getDisputeDetails from '@salesforce/apex/InvoiceDisputeService.getDisputeDetails';

export default class InvoiceDisputeAction extends LightningElement {
    _recordId;
    isLoading = false;
    errorDetails = '';
    disputeData = null;

    @api 
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.checkDisputeStatus();
        }
    }

    async checkDisputeStatus() {
        this.isLoading = true;
        this.errorDetails = '';
        this.disputeData = null;

        try {
            this.disputeData = await getDisputeDetails({ invoiceId: this.recordId });
        } catch (error) {
            this.errorDetails = error?.body?.message || error?.message || 'An unknown error occurred while fetching dispute details.';
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}