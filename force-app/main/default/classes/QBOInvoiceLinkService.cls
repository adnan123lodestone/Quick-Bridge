public with sharing class QBOInvoiceLinkService {
    @TestVisible private static List<Field_Mapping__mdt> testFieldMappings;

    public class InvoiceLinkResult {
        public String paymentLink { get; set; }
        public String message { get; set; }
        public Boolean retrieved { get; set; }
    }

    // Retrieves a QBO-hosted Invoice link after a successful POST. It intentionally
    // never triggers another Invoice create/update when this follow-up call fails.
    public static InvoiceLinkResult retrieveAndPersist(
        Id recordId,
        String objectApiName,
        String quickBooksInvoiceId
    ) {
        InvoiceLinkResult result = new InvoiceLinkResult();
        result.retrieved = false;
        if (recordId == null || String.isBlank(objectApiName) || String.isBlank(quickBooksInvoiceId)) {
            result.message = 'QuickBooks invoice synced, but a payment link is not available.';
            return result;
        }

        try {
            if (Test.isRunningTest() && testFieldMappings != null) {
                QBOInvoiceMappingResolver.setTestFieldMappingRows(testFieldMappings);
            }
            QBOInvoiceMappingResolver.ResolverResult mapping = QBOInvoiceMappingResolver.resolve(objectApiName);
            String paymentField = resolveWritablePaymentLinkField(objectApiName, mapping.invoiceLinkField);
            result.paymentLink = getStoredPaymentLink(recordId, objectApiName, paymentField);

            HttpResponse response = QuickBooksAuthHandler.makeApiCall(
                'GET',
                '/invoice/' + EncodingUtil.urlEncode(quickBooksInvoiceId, 'UTF-8') + '?include=invoiceLink',
                null
            );
            if (response == null || response.getStatusCode() != 200) {
                ErrorLogUtility.logCalloutFailure(
                    'QuickBooks', 'QBOInvoiceLinkService.retrieveAndPersist',
                    'QuickBooks invoice-link retrieval failed.',
                    response == null ? null : response.getStatusCode(), objectApiName, recordId
                );
                result.message = 'QuickBooks invoice synced, but the payment link could not be retrieved.';
                return result;
            }

            String invoiceLink = extractInvoiceLink(response.getBody());
            if (String.isBlank(invoiceLink)) {
                result.message = String.isBlank(result.paymentLink)
                    ? 'QuickBooks invoice synced. A payment link is not available for this invoice.'
                    : 'QuickBooks invoice synced. The existing payment link was retained.';
                return result;
            }

            persistPaymentLink(recordId, objectApiName, paymentField, invoiceLink);
            result.paymentLink = invoiceLink;
            result.retrieved = true;
            result.message = 'QuickBooks invoice synced and payment link retrieved.';
            return result;
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBooks', 'QBOInvoiceLinkService.retrieveAndPersist', e, objectApiName, recordId);
            result.message = 'QuickBooks invoice synced, but the payment link could not be retrieved.';
            return result;
        } finally {
            if (Test.isRunningTest() && testFieldMappings != null) {
                QBOInvoiceMappingResolver.clearTestFieldMappingRows();
            }
        }
    }

    @TestVisible
    private static String extractInvoiceLink(String responseBody) {
        if (String.isBlank(responseBody)) return null;
        try {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> invoice = response == null ? null : (Map<String, Object>) response.get('Invoice');
            Object linkValue = invoice == null ? null : invoice.get('InvoiceLink');
            String link;
            if (linkValue instanceof String) {
                link = (String) linkValue;
            } else if (linkValue instanceof Map<String, Object>) {
                Map<String, Object> linkMap = (Map<String, Object>) linkValue;
                link = String.valueOf(linkMap.containsKey('Link') ? linkMap.get('Link') : linkMap.get('Url'));
            }
            return isHttpsUrl(link) ? link : null;
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Boolean isHttpsUrl(String value) {
        if (String.isBlank(value)) return false;
        try {
            Url parsed = new Url(value);
            return parsed.getProtocol() == 'https' && String.isNotBlank(parsed.getHost());
        } catch (Exception e) {
            return false;
        }
    }

    private static String resolveWritablePaymentLinkField(String objectApiName, String configuredField) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null || String.isBlank(configuredField) || configuredField.contains('.')) {
            throw new QBOInvoiceMappingResolver.ResolverException('Configure an inbound InvoiceLink field mapping.');
        }
        Schema.SObjectField fieldToken = objectType.getDescribe().fields.getMap().get(configuredField.toLowerCase());
        if (fieldToken == null || !objectType.getDescribe().isUpdateable() || !fieldToken.getDescribe().isUpdateable()) {
            throw new QBOInvoiceMappingResolver.ResolverException('You do not have update access to the configured InvoiceLink field.');
        }
        return fieldToken.getDescribe().getName();
    }

    private static String getStoredPaymentLink(Id recordId, String objectApiName, String fieldName) {
        List<SObject> rows = Database.query(
            'SELECT Id, ' + fieldName + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1'
        );
        Object value = rows.isEmpty() ? null : rows[0].get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static void persistPaymentLink(Id recordId, String objectApiName, String fieldName, String paymentLink) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        SObject updateRecord = objectType.newSObject(recordId);
        updateRecord.put(fieldName, paymentLink);
        QuickBooksInvoiceHandler.setBatchContext(true);
        try {
            update updateRecord;
        } finally {
            QuickBooksInvoiceHandler.setBatchContext(false);
        }
    }
}
