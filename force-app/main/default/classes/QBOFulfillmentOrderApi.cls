global with sharing class QBOFulfillmentOrderApi {
    global class InvoiceLinkResult {
        global Boolean success { get; set; }
        global Id recordId { get; set; }
        global String objectApiName { get; set; }
        global Id orderSummaryId { get; set; }
        global String quickBooksInvoiceId { get; set; }
        global String paymentLink { get; set; }
        global String message { get; set; }
    }

    global static InvoiceLinkResult syncOrderSummaryAndGetPaymentLink(Id recordId) {
        String objectApiName = recordId == null
            ? null
            : recordId.getSObjectType().getDescribe().getName();
        return syncRecordAndGetPaymentLink(recordId, objectApiName);
    }

    global static InvoiceLinkResult syncRecordAndGetPaymentLink(Id recordId, String objectApiName) {
        InvoiceLinkResult result = new InvoiceLinkResult();
        result.recordId = recordId;
        result.objectApiName = objectApiName;
        result.orderSummaryId = recordId;
        try {
            QBORecordInvoiceSyncService.SyncResult syncResult = QBORecordInvoiceSyncService.sync(recordId, objectApiName);
            result.success = true;
            result.quickBooksInvoiceId = syncResult.quickBooksId;
            QBOInvoiceLinkService.InvoiceLinkResult linkResult =
                QBOInvoiceLinkService.retrieveAndPersist(recordId, syncResult.objectApiName, syncResult.quickBooksId);
            result.paymentLink = linkResult.paymentLink;
            result.message = linkResult.message;
        } catch (Exception e) {
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBOFulfillmentOrderApi.syncRecordAndGetPaymentLink',
                e,
                objectApiName,
                recordId
            );
            result.success = false;
            result.message = 'QuickBooks Invoice sync failed.';
        }
        return result;
    }
}
