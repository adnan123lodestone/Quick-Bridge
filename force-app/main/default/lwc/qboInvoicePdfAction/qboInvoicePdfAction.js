import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { RefreshEvent } from "lightning/refresh";
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

  connectedCallback() {
    this.loadPanel();
  }

  loadPanel() {
    if (!this.recordId || !this.objectApiName) {
      this.panelMessage = "PDF download is available on saved records.";
      return;
    }

    this.isPanelLoading = true;
    getPanelData({ recordId: this.recordId, objectApiName: this.objectApiName })
      .then((data) => {
        this.isConfigured = data.isConfigured;
        this.qboIdPresent = data.qboIdPresent;
        this.showSyncToQbo = data.showSyncToQbo;
        this.showSyncFromQbo = data.showSyncFromQbo;
        this.panelMessage = data.message || "";
      })
      .catch((error) => {
        this.isConfigured = false;
        this.panelMessage =
          error.body?.message ||
          error.message ||
          "Failed to load QBO Invoice PDF panel.";
      })
      .finally(() => {
        this.isPanelLoading = false;
      });
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
          result.message || "Record synced to QBO.",
          "success"
        );
        this.loadPanel();
        this.dispatchEvent(new RefreshEvent());
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
          result.message || "Sync from QBO queued.",
          "success"
        );
        this.dispatchEvent(new RefreshEvent());
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
