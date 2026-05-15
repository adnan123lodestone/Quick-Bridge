import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getPanelData from '@salesforce/apex/PaymentInvoiceRecordActionController.getPanelData';
import createInvoice from '@salesforce/apex/PaymentInvoiceRecordActionController.createInvoice';

export default class PaymentInvoiceRecordAction extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track paymentOptions = [];
    @track selectedGateway = '';
    @track panelMessage = '';
    @track isPanelLoading = false;
    @track isLoading = false;

    connectedCallback() {
        this.loadPanel();
    }

    get hasPaymentOptions() {
        return this.paymentOptions && this.paymentOptions.length > 0;
    }

    get createDisabled() {
        return this.isLoading || !this.selectedGateway;
    }

    async loadPanel() {
        if (!this.recordId || !this.objectApiName) {
            this.panelMessage = 'Invoice actions are available on saved records.';
            return;
        }

        this.isPanelLoading = true;
        try {
            const data = await getPanelData({
                recordId: this.recordId,
                objectApiName: this.objectApiName
            });
            this.paymentOptions = data?.paymentOptions || [];
            this.selectedGateway = data?.selectedGateway || (this.paymentOptions[0]?.value || '');
            this.panelMessage = data?.message || '';
        } catch (error) {
            this.paymentOptions = [];
            this.selectedGateway = '';
            this.panelMessage = this.getErrorMessage(error, 'Failed to load invoice action.');
            this.showToast('Unable to Load Invoice Action', this.panelMessage, 'error');
        } finally {
            this.isPanelLoading = false;
        }
    }

    handleGatewayChange(event) {
        this.selectedGateway = event.detail.value;
    }

    async handleCreateInvoice() {
        if (this.createDisabled) {
            return;
        }

        this.isLoading = true;
        try {
            const result = await createInvoice({
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                gateway: this.selectedGateway
            });

            if (!result?.success) {
                throw new Error(result?.message || 'Invoice could not be created.');
            }

            const detail = result.hostedInvoiceUrl
                ? `${result.message} Invoice URL: ${result.hostedInvoiceUrl}`
                : result.message;
            this.showToast('Invoice Created', detail, 'success');
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.showToast('Unable to Create Invoice', this.getErrorMessage(error, 'Invoice could not be created.'), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    getErrorMessage(error, fallback) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length) {
            const messages = error.body.map((item) => item?.message).filter(Boolean);
            if (messages.length) return messages.join(' ');
        }
        return error?.message || fallback;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}