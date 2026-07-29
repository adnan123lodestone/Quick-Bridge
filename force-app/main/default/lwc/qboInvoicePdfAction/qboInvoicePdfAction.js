import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { RefreshEvent } from "lightning/refresh";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getPanelData from "@salesforce/apex/QBOInvoicePdfActionController.getPanelData";
import downloadPdf from "@salesforce/apex/QBOInvoicePdfActionController.downloadPdf";
import syncToQbo from "@salesforce/apex/QBOInvoicePdfActionController.syncToQbo";
import syncFromQbo from "@salesforce/apex/QBOInvoicePdfActionController.syncFromQbo";

export default class QboInvoicePdfAction extends LightningElement {
  @api recordId;
  @api objectApiName;

  @track isPanelLoading = false;
  @track isLoading = false;
  @track isSyncingTo = false;
  @track isSyncingFrom = false;
  @track isConfigured = false;
  @track qboIdPresent = false;
  @track showSyncToQbo = false;
  @track showSyncFromQbo = false;
  @track panelMessage = "";

  pollInterval = null;
  pollCount = 0;
  maxPolls = 8; // Poll up to 20 seconds (8 * 2.5s)

  @wire(getRecord, { recordId: "$recordId", layoutTypes: ["Full"], modes: ["View"] })
  wiredRecord({ error, data }) {
    if (data) {
      // Re-evaluate panel state whenever Lightning Data Service updates the record
      this.loadPanel(true);
    }
  }

  connectedCallback() {
    this.loadPanel();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  loadPanel(isPolling = false) {
    if (!this.recordId || !this.objectApiName) {
      this.panelMessage = "PDF download is available on saved records.";
      return Promise.resolve();
    }

    if (!isPolling) {
      this.isPanelLoading = true;
    }

    return getPanelData({ recordId: this.recordId, objectApiName: this.objectApiName, timestamp: String(Date.now()) })
      .then((data) => {
        this.isConfigured = data.isConfigured;
        const previousQboIdState = this.qboIdPresent;
        this.qboIdPresent = data.qboIdPresent;
        this.showSyncToQbo = data.showSyncToQbo;
        this.showSyncFromQbo = data.showSyncFromQbo;
        this.panelMessage = data.message || "";

        if (this.qboIdPresent) {
          if (!previousQboIdState && isPolling) {
            this.showToast(
              "Sync Complete",
              "QuickBooks ID linked. PDF Download is now available!",
              "success"
            );
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(new RefreshEvent());
          }
          this.stopPolling();
        }
      })
      .catch((error) => {
        this.isConfigured = false;
        this.panelMessage =
          error.body?.message ||
          error.message ||
          "Failed to load QBO Invoice PDF panel.";
      })
      .finally(() => {
        if (!isPolling) {
          this.isPanelLoading = false;
        }
      });
  }

  startPolling() {
    this.stopPolling();
    this.pollCount = 0;
    this.pollInterval = setInterval(() => {
      this.pollCount++;
      if (this.pollCount > this.maxPolls) {
        this.stopPolling();
        return;
      }
      this.loadPanel(true);
    }, 2500);
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  get isDownloadDisabled() {
    return (
      this.isLoading ||
      this.isSyncingTo ||
      this.isSyncingFrom ||
      !this.qboIdPresent
    );
  }

  get isSyncToDisabled() {
    return this.isLoading || this.isSyncingTo || this.isSyncingFrom;
  }

  get isSyncFromDisabled() {
    return (
      this.isLoading ||
      this.isSyncingTo ||
      this.isSyncingFrom ||
      !this.qboIdPresent
    );
  }

  get hasMessage() {
    return !!this.panelMessage;
  }

  get hasAnyAction() {
    return this.showSyncToQbo || this.showSyncFromQbo || true;
  }

  handleSyncToQbo() {
    if (this.isSyncToDisabled) return;

    this.isSyncingTo = true;
    syncToQbo({ recordId: this.recordId, objectApiName: this.objectApiName })
      .then((result) => {
        this.showToast(
          "Success",
          result.message || "Record successfully synced to QBO.",
          "success"
        );
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
        this.loadPanel(true);
      })
      .catch((error) => {
        this.showToast(
          "Error",
          error.body?.message || error.message || "Sync to QBO failed.",
          "error"
        );
      })
      .finally(() => {
        this.isSyncingTo = false;
      });
  }

  handleSyncFromQbo() {
    if (this.isSyncFromDisabled) return;

    this.isSyncingFrom = true;
    syncFromQbo({ recordId: this.recordId, objectApiName: this.objectApiName })
      .then((result) => {
        this.showToast(
          "Success",
          result.message || "Record successfully synced from QBO.",
          "success"
        );
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
        this.loadPanel(true);
      })
      .catch((error) => {
        this.showToast(
          "Error",
          error.body?.message || error.message || "Sync from QBO failed.",
          "error"
        );
      })
      .finally(() => {
        this.isSyncingFrom = false;
      });
  }

  handleDownload() {
    if (this.isDownloadDisabled) return;

    this.isLoading = true;
    downloadPdf({ recordId: this.recordId, objectApiName: this.objectApiName })
      .then((result) => {
        this.showToast(
          "Success",
          result.message || "PDF saved to Files.",
          "success"
        );
        notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      })
      .catch((error) => {
        this.showToast(
          "Error",
          error.body?.message || error.message || "PDF download failed.",
          "error"
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}