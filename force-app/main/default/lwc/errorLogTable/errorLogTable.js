import { LightningElement, api, wire, track } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getDynamicLogs from "@salesforce/apex/ErrorLogUtility.getDynamicLogs";
import retryError from "@salesforce/apex/RetryDispatcher.retryError";
import updateRetryCount from "@salesforce/apex/ErrorLogUtility.updateRetryCount";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class ErrorLogTable extends LightningElement {
  @api gatewayName;
  @track allColumns = [];
  @track retriedColumns = [];
  @track freshLogs = []; // Retry_Count__c == 0 (only for QBO/Shopify)
  @track retriedLogs = []; // Retry_Count__c > 0  (only for QBO/Shopify)
  @track simpleLogs = []; // all logs for non‑retryable gateways
  @track paginatedFreshLogs = [];
  @track isRefreshing = true;

  // Pagination for fresh logs (only for QBO/Shopify)
  @track currentPage = 1;
  @track pageSize = 10;
  @track totalFresh = 0;
  @track totalPages = 0;

  wiredLogsResult;

  // Helper to determine if this gateway supports retry (QBO/Shopify)
  get isRetryableGateway() {
    return this.gatewayName === "QuickBooks" || this.gatewayName === "Shopify";
  }

  @wire(getDynamicLogs, { gatewayName: "$gatewayName" })
  wiredLogs(result) {
    this.wiredLogsResult = result;
    const { error, data } = result;

    if (data) {
      // Build dynamic columns from field set
      let tempCols = [...data.columns];
      tempCols = tempCols.filter(
        (col) => col.fieldName !== "Name" && col.fieldName !== "Name"
      );

      let nameColumn = {
        label: "Error Log Number",
        fieldName: "recordUrl",
        type: "url",
        typeAttributes: {
          label: { fieldName: "Name" },
          target: "_blank"
        },
        initialWidth: 160
      };

      let baseColumns = [nameColumn, ...tempCols];
      let retryColumn = {
        label: "Retry",
        type: "action",
        fixedWidth: 70,
        typeAttributes: {
          rowActions: [
            { label: "Retry", name: "retry", iconName: "utility:refresh" }
          ]
        }
      };

      if (this.isRetryableGateway) {
        this.allColumns = [...baseColumns, retryColumn];
      } else {
        this.allColumns = [...baseColumns];
      }
      this.retriedColumns = [...baseColumns]; // no retry column

      // Process records
      let processedData = data.records.map((record) => {
        let newRec = { ...record };
        let cleanRec = {};
        for (let key in newRec) {
          if (Object.prototype.hasOwnProperty.call(newRec, key)) {
            let cleanKey = key;
            // Remove namespace prefix if present (e.g., QuickBridgeTLG__Field__c -> Field__c)
            if (key.includes("__")) {
              let parts = key.split("__");
              if (
                parts.length >= 2 &&
                !key.endsWith("__c") &&
                !key.endsWith("__r")
              ) {
                // This is a namespace prefix (not a field ending with __c or __r)
                cleanKey = parts.slice(1).join("__");
              }
            }
            cleanRec[cleanKey] = newRec[key];
          }
        }

        cleanRec.recordUrl = `/lightning/r/${cleanRec.Id}/view`;

        // Mobile fields
        let mobileFields = [];
        data.columns.forEach((col) => {
          if (col.type === "url") {
            let originalField = col.fieldName.replace("_Url", "");
            // Try to get value from cleanRec first, then from newRec
            let value = cleanRec[originalField] || newRec[originalField];
            if (value) {
              cleanRec[col.fieldName] = `/lightning/r/${value}/view`;
              let relationName = originalField.endsWith("__c")
                ? originalField.replace("__c", "__r")
                : originalField.replace("Id", "");
              cleanRec[originalField + "_Name"] =
                cleanRec[relationName] && cleanRec[relationName].Name
                  ? cleanRec[relationName].Name
                  : value;
            } else {
              cleanRec[col.fieldName] = "";
              cleanRec[originalField + "_Name"] = "";
            }
          }

          if (col.fieldName !== "Name" && col.fieldName !== "recordUrl") {
            let isUrl = col.type === "url";
            let isDate = col.type === "date";
            let displayValue = isUrl
              ? cleanRec[col.fieldName.replace("_Url", "") + "_Name"]
              : cleanRec[col.fieldName];
            mobileFields.push({
              label: col.label,
              value: displayValue,
              isDate: isDate,
              isUrl: isUrl && cleanRec[col.fieldName] !== "",
              urlLink: cleanRec[col.fieldName],
              urlLabel: displayValue
            });
          }
        });
        cleanRec.mobileFields = mobileFields;
        return cleanRec;
      });

      if (this.isRetryableGateway) {
        // Split based on Retry_Count__c
        this.freshLogs = processedData.filter(
          (rec) => (rec.Retry_Count__c || 0) === 0
        );
        this.retriedLogs = processedData.filter(
          (rec) => (rec.Retry_Count__c || 0) > 0
        );
        this.totalFresh = this.freshLogs.length;
        this.totalPages = Math.ceil(this.totalFresh / this.pageSize);
        this.updatePagination();
      } else {
        // Simple mode: all logs in one table, no pagination needed
        this.simpleLogs = processedData;
      }
      this.isRefreshing = false;
    } else if (error) {
      console.error("Error fetching logs:", error);
      this.isRefreshing = false;
    }
  }

  updatePagination() {
    let start = (this.currentPage - 1) * this.pageSize;
    let end = this.currentPage * this.pageSize;
    this.paginatedFreshLogs = this.freshLogs.slice(start, end);
  }

  handleRefresh() {
    this.isRefreshing = true;
    refreshApex(this.wiredLogsResult).finally(() => {
      this.isRefreshing = false;
    });
  }

  handlePrevious() {
    if (this.currentPage > 1) {
      this.currentPage--;
      this.updatePagination();
    }
  }

  handleNext() {
    if (this.currentPage < this.totalPages) {
      this.currentPage++;
      this.updatePagination();
    }
  }

  get isFirstPage() {
    return this.currentPage === 1;
  }
  get isLastPage() {
    return this.currentPage === this.totalPages || this.totalPages === 0;
  }
  get hasFreshLogs() {
    return this.totalFresh > 0;
  }
  get hasRetriedLogs() {
    return this.retriedLogs.length > 0;
  }
  get hasSimpleLogs() {
    return this.simpleLogs.length > 0;
  }
  get totalSimpleErrors() {
    return this.simpleLogs ? this.simpleLogs.length : 0;
  }

  async handleRowAction(event) {
    const action = event.detail.action;
    const row = event.detail.row;
    if (action.name !== "retry") return;

    const errorLogId = row.Id;
    this.isRefreshing = true;

    try {
      const result = await retryError({ errorLogId });
      this.showToast("Success", result, "success");
      await this.handleRefresh();
    } catch (error) {
      let errorMsg = error.body?.message || "Retry failed";
      if (errorMsg.includes("not retryable")) {
        try {
          await updateRetryCount({ errorLogId });
          this.showToast(
            "Non‑Retryable Error",
            "This error is not retryable. Retry count has been increased.",
            "warning"
          );
        } catch {
          this.showToast("Error", "Failed to update retry count.", "error");
        }
      } else {
        this.showToast("Error", errorMsg, "error");
      }
      await this.handleRefresh();
    } finally {
      this.isRefreshing = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
