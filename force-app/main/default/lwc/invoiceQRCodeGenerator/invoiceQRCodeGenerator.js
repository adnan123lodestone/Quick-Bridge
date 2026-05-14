import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import generateAndSaveQRCode from '@salesforce/apex/InvoiceQRService.generateAndSaveQRCode';

export default class InvoiceQRCodeGenerator extends LightningElement {
    @api recordId;
    isLoading = false;
    errorMessage = '';
    qrData = {};

    async generateQR() {
        this.isLoading = true;
        this.errorMessage = '';
        this.qrData = {};

        try {
            this.qrData = await generateAndSaveQRCode({ invoiceId: this.recordId });
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Failed to generate QR Code.';
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}