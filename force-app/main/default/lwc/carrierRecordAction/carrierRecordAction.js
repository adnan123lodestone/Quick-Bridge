import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveCarriers from '@salesforce/apex/CarrierRecordActionController.getActiveCarriers';
import getActionsForObject from '@salesforce/apex/CarrierRecordActionController.getActionsForObject';
import updateCarrierType from '@salesforce/apex/CarrierRecordActionController.updateCarrierType';
import runAction from '@salesforce/apex/CarrierRecordActionController.runAction';
import applyValidatedAddress from '@salesforce/apex/CarrierRecordActionController.applyValidatedAddress';
import selectRateQuote from '@salesforce/apex/CarrierRecordActionController.selectRateQuote';

export default class CarrierRecordAction extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track carrierType = null;
    @track actions = [];
    @track isLoading = false;
    @track isPanelLoading = false;

    @track result = null;
    @track rateQuotes = [];
    @track showRateModal = false;
    @track showConfirmModal = false;
    @track confirmedAddress = null;
    @track activeActionName = null;

    @track carrierOptions = [];

    connectedCallback() {
        this.loadActiveCarriersAndPanel();
    }

    loadActiveCarriersAndPanel() {
        this.isPanelLoading = true;
        getActiveCarriers()
            .then((carriers) => {
                const options = [];
                if (carriers.fedexActive) options.push({ label: 'FedEx', value: 'FedEx' });
                if (carriers.upsActive)   options.push({ label: 'UPS',   value: 'UPS'   });
                this.carrierOptions = options;
                return getActionsForObject({ recordId: this.recordId, objectApiName: this.objectApiName });
            })
            .then((data) => {
                this.carrierType = data.carrierType;
                this.actions = data.actions || [];
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message || 'Failed to load carrier actions.', 'error');
            })
            .finally(() => {
                this.isPanelLoading = false;
            });
    }

    get hasActiveCarriers() {
        return this.carrierOptions && this.carrierOptions.length > 0;
    }

    get hasActions() {
        return this.actions && this.actions.length > 0;
    }

    get noActionsMessage() {
        if (!this.carrierType) {
            return 'Select a carrier type to see available actions.';
        }
        return 'No field mappings configured for ' + this.carrierType + ' on this object. Configure mappings in the Quickbridge settings.';
    }

    handleCarrierChange(event) {
        const newCarrier = event.detail.value;
        if (newCarrier === this.carrierType) return;

        this.isLoading = true;
        updateCarrierType({ recordId: this.recordId, objectApiName: this.objectApiName, carrierType: newCarrier })
            .then(() => {
                this.carrierType = newCarrier;
                return getActionsForObject({ recordId: this.recordId, objectApiName: this.objectApiName });
            })
            .then((data) => {
                this.actions = data.actions || [];
                this.showToast('Success', 'Carrier type updated to ' + newCarrier + '.', 'success');
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message || 'Failed to update carrier type.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleActionClick(event) {
        const actionName = event.currentTarget.dataset.action;
        this.activeActionName = actionName;
        this.isLoading = true;
        this.result = null;
        this.rateQuotes = [];

        const apexActionName = (actionName === 'validateAddress' || actionName === 'validateAddressAndUpdate')
            ? 'validateAddress'
            : actionName;

        runAction({ recordId: this.recordId, objectApiName: this.objectApiName, actionName: apexActionName })
            .then((res) => {
                this.result = res;

                if (!res.success) {
                    this.showToast('Error', res.message || 'Action failed.', 'error');
                    return;
                }

                if (actionName === 'validateAddress' && res.correctedAddress) {
                    this.confirmedAddress = res.correctedAddress;
                    this.showConfirmModal = true;
                    return;
                }

                if (actionName === 'getRateQuote' && res.rateQuotes && res.rateQuotes.length) {
                    this.rateQuotes = res.rateQuotes.map((q) => ({ ...q, selected: false }));
                    this.showRateModal = true;
                    return;
                }

                let message = res.message || 'Action completed successfully.';
                if (res.trackingNumber) message += ' Tracking: ' + res.trackingNumber;
                if (res.fileId) message += ' Label stored.';
                this.showToast('Success', message, 'success');
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message || 'Unexpected error.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleConfirmAddress() {
        this.showConfirmModal = false;
        this.isLoading = true;
        applyValidatedAddress({
            recordId: this.recordId,
            objectApiName: this.objectApiName,
            validatedAddress: this.confirmedAddress
        })
            .then((res) => {
                if (res.success) {
                    this.showToast('Success', 'Validated address applied to record.', 'success');
                } else {
                    this.showToast('Error', res.message || 'Could not apply address.', 'error');
                }
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message || 'Unexpected error.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancelConfirmModal() {
        this.showConfirmModal = false;
        this.showToast('Info', 'Address validation result discarded. Salesforce record was not updated.', 'info');
    }

    handleRateQuoteSelect(event) {
        const quoteId = event.currentTarget.dataset.quoteId;
        this.rateQuotes = this.rateQuotes.map((q) => ({ ...q, selected: q.rateQuoteId === quoteId }));
    }

    handleConfirmRateQuote() {
        const selected = this.rateQuotes.find((q) => q.selected);
        if (!selected) {
            this.showToast('Select a Rate', 'Please select a rate option before confirming.', 'warning');
            return;
        }

        this.isLoading = true;
        selectRateQuote({ rateQuoteId: selected.rateQuoteId, targetRecordId: this.recordId, targetObjectApiName: this.objectApiName })
            .then((res) => {
                this.showRateModal = false;
                if (res.success) {
                    this.showToast('Success', 'Rate quote applied: ' + selected.serviceName + ' (' + selected.totalNetCharge + ' ' + selected.currencyCode + ')', 'success');
                } else {
                    this.showToast('Error', res.message || 'Could not apply rate quote.', 'error');
                }
            })
            .catch((error) => {
                this.showToast('Error', error.body?.message || error.message || 'Unexpected error.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancelRateModal() {
        this.showRateModal = false;
    }

    get confirmedAddressLines() {
        if (!this.confirmedAddress) return [];
        const addr = this.confirmedAddress;

        const rawStreet = addr.streetLines || addr.streetLinesToken || addr.STREETLINESTOKEN || addr.STREETLINES;
        const street = Array.isArray(rawStreet)
            ? rawStreet.filter(Boolean).join(', ')
            : (rawStreet || null);

        const fields = [
            { key: 'Street',      value: street },
            { key: 'City',        value: addr.city        || addr.CITY        || null },
            { key: 'State',       value: addr.stateOrProvinceCode || addr.STATEORPROVINCECODE || null },
            { key: 'Postal Code', value: addr.postalCode  || addr.POSTALCODE  || null },
            { key: 'Country',     value: addr.countryCode || addr.COUNTRYCODE || null },
            { key: 'Residential', value: addr.residential != null ? String(addr.residential)
                                        : (addr.CLASSIFICATION ? addr.CLASSIFICATION : null) },
        ];

        return fields.filter(f => f.value != null && f.value !== '');
    }

    get hasRateQuotes() {
        return this.rateQuotes && this.rateQuotes.length > 0;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}