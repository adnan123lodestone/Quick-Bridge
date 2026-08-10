import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { RefreshEvent } from "lightning/refresh";
import syncToQuickBooks from "@salesforce/apex/QBOrderSummaryRecordActionController.syncToQuickBooks";

export default class OrderSummarySyncToQbAction extends LightningElement {
  @api recordId;

  isRunning = false;

  @api
  async invoke() {
    if (this.isRunning || !this.recordId) {
      return;
    }

    this.isRunning = true;

    try {
      const response = await syncToQuickBooks({ orderSummaryId: this.recordId });
      if (!response?.success) {
        throw new Error(
          response?.message || "Order Summary could not be synced to QuickBooks."
        );
      }

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Synced To QuickBooks",
          message: response.message,
          variant: "success"
        })
      );
      this.dispatchEvent(new RefreshEvent());
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Sync To QuickBooks Failed",
          message: this.getErrorMessage(error),
          variant: "error"
        })
      );
    } finally {
      this.isRunning = false;
    }
  }

  getErrorMessage(error) {
    const body = error?.body;

    if (typeof body?.message === "string" && body.message) {
      return body.message;
    }

    if (Array.isArray(body) && body.length > 0) {
      const messages = body
        .map((item) => item?.message)
        .filter((message) => typeof message === "string" && message);
      if (messages.length > 0) {
        return messages.join(" ");
      }
    }

    if (typeof error?.message === "string" && error.message) {
      return error.message;
    }

    return "Order Summary could not be synced to QuickBooks.";
  }
}