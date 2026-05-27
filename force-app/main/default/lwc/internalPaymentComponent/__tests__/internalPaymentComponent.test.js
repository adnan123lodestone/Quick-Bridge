import { createElement } from "lwc";
import PaymentComponent from "c/internalPaymentComponent";
import getCheckoutProviders from "@salesforce/apex/PaymentCheckoutController.getCheckoutProviders";

jest.mock(
  "@salesforce/apex/PaymentCheckoutController.getCheckoutProviders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PaymentCheckoutController.initializePayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PaymentCheckoutController.executePayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.CardPayment_lables",
  () => ({
    default: "Name|Card Number|CVV|Month|Year|Address|City|State|Zip|Country"
  }),
  { virtual: true }
);

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe("c-internal-payment-component descriptor rendering", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders card providers from descriptor renderer mode and button label", async () => {
    getCheckoutProviders.mockResolvedValue([
      {
        connectorKey: "stripe",
        label: "Stripe",
        active: true,
        configured: true,
        actionType: "stripeElements",
        buttonLabel: "Pay securely",
        displayOrder: 1,
        config: {
          stripeJsUrl: "https://js.stripe.com/v3/",
          publishableKey: "pk_test"
        }
      }
    ]);

    const element = createElement("c-internal-payment-component", {
      is: PaymentComponent
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "Stripe Secure Card Entry"
    );
    const buttonLabels = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].map((button) => button.label);
    expect(buttonLabels).toContain("Pay securely");
  });
});
