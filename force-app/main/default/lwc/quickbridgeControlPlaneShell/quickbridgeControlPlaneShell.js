import { LightningElement, api } from "lwc";

export default class QuickbridgeControlPlaneShell extends LightningElement {
  @api quickBridgeLogo;
  @api isLoggedIn = false;
  @api currentScreen = "login";
  @api isSchedulerAvailable = false;
  @api showSidebarBackButton = false;

  get navHomeClass() {
    return this.currentScreen === "tiles" ? "nav-button active" : "nav-button";
  }

  get navDashboardClass() {
    return this.currentScreen === "dashboard"
      ? "nav-button active"
      : "nav-button";
  }

  get navReportingClass() {
    return this.currentScreen === "reporting"
      ? "nav-button active"
      : "nav-button";
  }

  get navMappingClass() {
    return this.currentScreen === "mapping"
      ? "nav-button active"
      : "nav-button";
  }

  get navSettingsClass() {
    return this.currentScreen === "config" ? "nav-button active" : "nav-button";
  }

  get navSchedulerClass() {
    return this.currentScreen === "scheduler"
      ? "nav-button active"
      : "nav-button";
  }

  handleNavigate(event) {
    this.dispatchEvent(
      new CustomEvent("navigate", {
        detail: { screen: event.currentTarget.dataset.screen }
      })
    );
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("back"));
  }

  handleLogin() {
    this.dispatchEvent(new CustomEvent("login"));
  }

  handleLogout() {
    this.dispatchEvent(new CustomEvent("logout"));
  }
}
