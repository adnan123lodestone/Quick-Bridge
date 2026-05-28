import { createElement } from "lwc";
import fs from "fs";
import path from "path";
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

  it("keeps the parent descriptor-driven without provider fallback branches", () => {
    const source = fs.readFileSync(
      path.join(__dirname, "../internalPaymentComponent.js"),
      "utf8"
    );

    expect(source).not.toContain("FALLBACK_PAYMENT_PROVIDERS");
    expect(source).not.toContain("isAuthorizeNetSelected");
    expect(source).not.toContain("isStripeSelected");
    expect(source).not.toMatch(/authorizenet:\s*["']acceptJs["']/);
    expect(source).not.toMatch(/stripe:\s*["']stripeElements["']/);
    expect(source).not.toMatch(/paypal:\s*["']paypalButtons["']/);
  });

  it("renders an unknown hosted provider from descriptors without parent JS changes", async () => {
    getCheckoutProviders.mockResolvedValue([
      {
        connectorKey: "newhosted",
        label: "New Hosted Gateway",
        active: true,
        configured: true,
        actionType: "hosted",
        buttonLabel: "Continue Hosted",
        displayOrder: 1,
        config: {}
      }
    ]);

    const element = createElement("c-internal-payment-component", {
      is: PaymentComponent
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("New Hosted Gateway");
    const buttonLabels = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].map((button) => button.label);
    expect(buttonLabels).toContain("Continue Hosted");
  });
});
