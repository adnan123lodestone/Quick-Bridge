import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import getOrderPaymentContext from "@salesforce/apex/OrderPaymentActionController.getOrderPaymentContext";

export default class OrderPaymentAction extends LightningElement {
  _recordId;

  isLoading = false;
  loadError = "";
  totalAmount;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    this._recordId = value;
    if (value) {
      this.loadOrderContext();
    }
  }

  get hasLoadError() {
    return !!this.loadError;
  }

  get showLoadingState() {
    return this.isLoading;
  }

  get isReady() {
    return !!this.recordId && this.totalAmount != null;
  }

  handlePaymentSuccessModalClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
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

    return "Order details could not be loaded.";
  }

  async loadOrderContext() {
    this.isLoading = true;
    this.loadError = "";

    try {
      const response = await getOrderPaymentContext({ orderId: this.recordId });
      this.totalAmount = response?.totalAmount;

      if (this.totalAmount == null) {
        this.loadError = "Order TotalAmount is not available for this order.";
      }
    } catch (error) {
      this.totalAmount = undefined;
      this.loadError = this.getErrorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }
}