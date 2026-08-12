import { LightningElement, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getScheduledJobs from "@salesforce/apex/GenericSchedulerController.getScheduledJobs";
import scheduleJob from "@salesforce/apex/GenericSchedulerController.scheduleJob";
import stopConnectorSchedules from "@salesforce/apex/GenericSchedulerController.stopConnectorSchedules";
import getSyncSettingsSummary from "@salesforce/apex/GenericSchedulerController.getSyncSettingsSummary";
import getRecentRuns from "@salesforce/apex/GenericSchedulerController.getRecentRuns";
import togglePauseStatus from "@salesforce/apex/GenericSchedulerController.togglePauseStatus";
import deleteJob from "@salesforce/apex/GenericSchedulerController.deleteJob";
import editJob from "@salesforce/apex/GenericSchedulerController.editJob";
export default class ShopifySchedulerComponent extends LightningElement {
  connectorKey = "shopify";
  @track isNewScheduleView = false;
  @track hasJobs = false;
  wiredJobsResult;

  @track searchKey = "";
  @track statusFilter = "all";
  @track allJobs = [];
  @track filteredJobs = [];
  @track selectedJobId = null;
  @track syncSettings = { objects: "", direction: "", type: "" };
  @track freqValue = "10";
  @track freqType = "Minutes";
  @track recentRuns = [];
  @track isEditMode = false;
  @track editFreqValue = "10";
  @track editFreqType = "Minutes";
  @track syncObjects = [
    {
      id: "Customers",
      label: "Customers",
      icon: "utility:people",
      isSelected: true,
      btnClass: "obj-btn selected"
    },
    {
      id: "Orders",
      label: "Orders",
      icon: "utility:orders",
      isSelected: false,
      btnClass: "obj-btn"
    },
    {
      id: "Products",
      label: "Products",
      icon: "utility:product",
      isSelected: false,
      btnClass: "obj-btn"
    }
  ];

  statusOptions = [
    { label: "All Status", value: "all" },
    { label: "Active", value: "active" },
    { label: "Paused", value: "paused" }
  ];

  frequencyOptions = [
    { label: "5", value: "5" },
    { label: "10", value: "10" },
    { label: "15", value: "15" },
    { label: "30", value: "30" },
    { label: "60", value: "60" }
  ];

  @wire(getScheduledJobs, { connectorKey: "$connectorKey" })
  wiredJobs(result) {
    this.wiredJobsResult = result;
    if (result.data) {
      this.hasJobs = result.data.length > 0;
      this.allJobs = result.data.map((job) => {
        let displayStatus = "Inactive";
        let badgeClass = "badge-inactive";

        if (
          [
            "WAITING",
            "ACQUIRED",
            "EXECUTING",
            "Active",
            "Ready",
            "Claimed",
            "Running"
          ].includes(job.status)
        ) {
          displayStatus = "Active";
          badgeClass = "badge-active";
        } else if (
          job.status === "PAUSED" ||
          job.status === "PAUSED_AND_WAITING"
        ) {
          displayStatus = "Paused";
          badgeClass = "badge-paused";
        }

        return {
          ...job,
          displayStatus: displayStatus,
          badgeClass: badgeClass
        };
      });

      this.applyFilters();
    } else if (result.error) {
      console.error("Error fetching Shopify jobs:", result.error);
    }
  }

  @wire(getSyncSettingsSummary, { connectorKey: "$connectorKey" })
  wiredSettings({ error, data }) {
    if (data) {
      this.syncSettings = data;
    } else if (error) {
      console.error("Error fetching Shopify sync settings:", error);
    }
  }

  @wire(getRecentRuns, { jobId: "$selectedJobId" })
  wiredRecentRuns({ error, data }) {
    if (data) {
      this.recentRuns = data;
    } else if (error) {
      console.error("Error fetching recent runs:", error);
      this.recentRuns = [];
    }
  }

  get hasRecentRuns() {
    return this.recentRuns && this.recentRuns.length > 0;
  }

  handleSearch(event) {
    this.searchKey = event.target.value.toLowerCase();
    this.applyFilters();
  }

  handleStatusChange(event) {
    this.statusFilter = event.detail.value;
    this.applyFilters();
  }

  applyFilters() {
    this.filteredJobs = this.allJobs
      .filter((job) => {
        const matchesSearch = job.name.toLowerCase().includes(this.searchKey);
        const matchesStatus =
          this.statusFilter === "all" ||
          job.displayStatus.toLowerCase() === this.statusFilter.toLowerCase();
        return matchesSearch && matchesStatus;
      })
      .map((job) => ({
        ...job,
        cardClass:
          job.id === this.selectedJobId ? "job-item active-job" : "job-item"
      }));
  }

  handleJobSelect(event) {
    this.selectedJobId = event.currentTarget.dataset.id;
    this.applyFilters();
  }

  @track isSfToShopifySync = false;

  handleSyncDirectionToggle(event) {
    this.isSfToShopifySync = event.target.checked;
  }

  handleNewSchedule() {
    this.isNewScheduleView = true;
    this.syncObjects = this.syncObjects.map((obj) => ({
      ...obj,
      isSelected: true,
      btnClass: "obj-btn selected"
    }));
    this.isSfToShopifySync = false;
    this.freqValue = "10";
    this.freqType = "Minutes";
  }

  handleBackToList() {
    this.isNewScheduleView = false;
    return refreshApex(this.wiredJobsResult);
  }

  async handleSetSchedule() {
    try {
      const selectedObj = this.syncObjects.find((obj) => obj.isSelected);
      const objectNameToSend = selectedObj ? selectedObj.id : "Customers";
      const newCreatedJobId = await scheduleJob({
        connectorKey: this.connectorKey,
        freqValue: this.freqValue,
        freqType: this.freqType,
        selectedObject: objectNameToSend,
        direction: this.isSfToShopifySync ? "Out" : "In"
      });

      this.showToast(
        "Success",
        "Shopify schedule created successfully!",
        "success"
      );
      this.selectedJobId = newCreatedJobId;
      this.isNewScheduleView = false;

      await refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.showToast("Error", error.body?.message, "error");
    }
  }

  async handleStopSchedule() {
    try {
      const result = await stopConnectorSchedules({
        connectorKey: this.connectorKey
      });
      this.showToast("Schedule Stopped", result, "info");
      return refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    }
    return undefined;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  get selectedJob() {
    if (this.allJobs && this.selectedJobId) {
      return this.allJobs.find((job) => job.id === this.selectedJobId);
    }
    return null;
  }

  get freqTypeOptions() {
    return [
      { label: "Minutes", value: "Minutes" },
      { label: "Hours", value: "Hours" },
      { label: "Days", value: "Days" },
      { label: "Weeks", value: "Weeks" },
      { label: "Months", value: "Months" }
    ];
  }

  handleValueChange(event) {
    this.freqValue = event.target.value;
  }

  handleTypeChange(event) {
    this.freqType = event.detail.value;
  }

  toggleObjectSelection(event) {
    const selectedId = event.currentTarget.dataset.id;
    this.syncObjects = this.syncObjects.map((obj) => ({
      ...obj,
      isSelected: obj.id === selectedId,
      btnClass: obj.id === selectedId ? "obj-btn selected" : "obj-btn"
    }));
  }

  handleEdit() {
    this.isEditMode = true;
  }

  handleCancelEdit() {
    this.isEditMode = false;
  }

  handleEditValueChange(event) {
    this.editFreqValue = event.target.value;
  }

  handleEditTypeChange(event) {
    this.editFreqType = event.detail.value;
  }

  async handlePause() {
    const isCurrentlyPaused = this.selectedJob?.displayStatus === "Paused";
    try {
      await togglePauseStatus({
        connectorKey: this.connectorKey,
        pauseIt: !isCurrentlyPaused
      });
      this.showToast(
        "Success",
        !isCurrentlyPaused
          ? "Scheduler Paused Successfully"
          : "Scheduler Resumed!",
        "success"
      );
      return refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.showToast("Error", error.body?.message, "error");
    }
    return undefined;
  }

  get pauseButtonLabel() {
    return this.selectedJob?.displayStatus === "Paused"
      ? "Resume Schedule"
      : "Pause Schedule";
  }

  get latestRunStats() {
    if (this.recentRuns && this.recentRuns.length > 0) {
      return this.recentRuns[0];
    }
    return {
      status: "N/A",
      processed: 0,
      failed: 0,
      icon: "utility:info",
      variant: ""
    };
  }

  async handleDelete() {
    try {
      await deleteJob({ jobName: this.selectedJob.name });
      this.showToast(
        "Success",
        "Shopify schedule deleted successfully",
        "success"
      );
      this.selectedJobId = null;
      this.isEditMode = false;
      return refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.showToast("Error", error.body?.message, "error");
    }
    return undefined;
  }

  async handleSaveEdit() {
    try {
      await editJob({
        connectorKey: this.connectorKey,
        jobName: this.selectedJob.name,
        freqValue: this.editFreqValue,
        freqType: this.editFreqType
      });
      this.showToast(
        "Success",
        "Shopify schedule updated successfully!",
        "success"
      );
      this.isEditMode = false;
      return refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.showToast("Error", error.body?.message, "error");
    }
    return undefined;
  }
}
