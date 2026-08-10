public with sharing class QBOInvoicePdfActionController {

    public class PanelData {
        @AuraEnabled public Boolean isConfigured;
        @AuraEnabled public Boolean qboIdPresent;
        @AuraEnabled public Boolean showSyncToQbo;
        @AuraEnabled public Boolean showSyncFromQbo;
        @AuraEnabled public String message;
        public PanelData() {
            isConfigured    = false;
            qboIdPresent    = false;
            showSyncToQbo   = false;
            showSyncFromQbo = false;
            message = '';
        }
    }

    public class ActionResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        public ActionResponse(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }

    // ── Panel load ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static PanelData getPanelData(Id recordId, String objectApiName) {
        try {
            PanelData data = new PanelData();

            QBOInvoiceMappingResolver.ResolverResult resolved = QBOInvoiceMappingResolver.resolve();

            if (!objectMatches(objectApiName, resolved.invoiceSourceObject)) {
                data.message =
                    'QBO Invoice PDF is not configured for this object (' + objectApiName + '). ' +
                    'The configured invoice source object is ' + resolved.invoiceSourceObject + '.';
                return data;
            }

            if (String.isBlank(resolved.qboIdField)) {
                data.message = 'No QBO Invoice Id field mapping found. Configure a QBO to SF mapping for the Invoice Id field.';
                return data;
            }

            data.isConfigured = true;

            String idDirection = resolved.qboIdFieldDirection;
            if (idDirection == 'Two-Way') {
                data.showSyncToQbo  = true;
                data.showSyncFromQbo = true;
            } else if (idDirection == 'SF to QBO') {
                data.showSyncToQbo  = true;
            } else if (idDirection == 'QBO to SF') {
                data.showSyncFromQbo = true;
            } else {
                data.showSyncToQbo  = true;
                data.showSyncFromQbo = true;
            }

            String qboId = fetchFieldValue(recordId, objectApiName, resolved.qboIdField);
            data.qboIdPresent = String.isNotBlank(qboId);

            if (!data.qboIdPresent) {
                data.message = 'This record has not been synced to QBO yet. Sync it to QBO before downloading the PDF.';
            }

            return data;

        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            logException('getPanelData', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        } catch (AuraHandledException e) {
            logException('getPanelData', e, objectApiName, recordId);
            throw e;
        } catch (Exception e) {
            logException('getPanelData', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Sync To QBO (outbound SF → QBO via work queue) ────────────────────────

    @AuraEnabled(cacheable=false)
    public static ActionResponse syncToQbo(Id recordId, String objectApiName) {
        try {
            QBOInvoiceMappingResolver.ResolverResult resolved = QBOInvoiceMappingResolver.resolve();
            assertObjectMatch(objectApiName, resolved.invoiceSourceObject);

            String stripped = stripNamespace(objectApiName);
            if (stripped.equalsIgnoreCase('order')) {
                QBOrderRecordActionController.ActionResponse resp = QBOrderRecordActionController.syncToQuickBooks(recordId);
                if (resp != null && !resp.success) {
                    throw new AuraHandledException(resp.message);
                }
                return new ActionResponse(true, resp != null && String.isNotBlank(resp.message) ? resp.message : 'Order successfully synced to QBO.');
            } else if (stripped.equalsIgnoreCase('ordersummary')) {
                QBOrderSummaryRecordActionController.ActionResponse resp = QBOrderSummaryRecordActionController.syncToQuickBooks(recordId);
                if (resp != null && !resp.success) {
                    throw new AuraHandledException(resp.message);
                }
                return new ActionResponse(true, resp != null && String.isNotBlank(resp.message) ? resp.message : 'Order Summary successfully synced to QBO.');
            }

            String qboId = fetchFieldValue(recordId, objectApiName, resolved.qboIdField);
            Boolean isInitialSync = String.isBlank(qboId);

            String lockPrefix = 'Invoice';

            IntegrationWorkService.enqueueQuickBooksWork(
                'InvoiceUpsert',
                objectApiName,
                recordId,
                lockPrefix + ':' + recordId,
                isInitialSync
            );

            return new ActionResponse(true,
                isInitialSync
                    ? 'Record queued to sync to QBO.'
                    : 'Record queued to update in QBO.'
            );

        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            logException('syncToQbo', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        } catch (AuraHandledException e) {
            logException('syncToQbo', e, objectApiName, recordId);
            throw e;
        } catch (Exception e) {
            logException('syncToQbo', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Sync From QBO (inbound QBO → SF via direct callout) ──────────────────

    @AuraEnabled(cacheable=false)
    public static ActionResponse syncFromQbo(Id recordId, String objectApiName) {
        try {
            QBOInvoiceMappingResolver.ResolverResult resolved = QBOInvoiceMappingResolver.resolve();
            assertObjectMatch(objectApiName, resolved.invoiceSourceObject);

            String stripped = stripNamespace(objectApiName);
            if (stripped.equalsIgnoreCase('order')) {
                QBOrderRecordActionController.ActionResponse resp = QBOrderRecordActionController.syncFromQuickBooks(recordId);
                if (resp != null && !resp.success) {
                    throw new AuraHandledException(resp.message);
                }
                return new ActionResponse(true, resp != null && String.isNotBlank(resp.message) ? resp.message : 'Order successfully synced from QBO.');
            } else if (stripped.equalsIgnoreCase('ordersummary')) {
                QBOrderSummaryRecordActionController.ActionResponse resp = QBOrderSummaryRecordActionController.syncFromQuickBooks(recordId);
                if (resp != null && !resp.success) {
                    throw new AuraHandledException(resp.message);
                }
                return new ActionResponse(true, resp != null && String.isNotBlank(resp.message) ? resp.message : 'Order Summary successfully synced from QBO.');
            }

            String qboId = fetchFieldValue(recordId, objectApiName, resolved.qboIdField);
            if (String.isBlank(qboId)) {
                throw new AuraHandledException(
                    'This record has no QBO Id. Sync it to QBO first before syncing back.'
                );
            }

            String externalEntity = IntegrationEntityRegistry.resolveExternalEntity(
                'qbonline', objectApiName, null, 'Invoice'
            );

            String endpoint = '/' + externalEntity.toLowerCase() + '/' + qboId;

            HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', endpoint, null);
            if (res == null || res.getStatusCode() != 200) {
                Integer code = res == null ? 0 : res.getStatusCode();
                throw new AuraHandledException(
                    'QBO returned HTTP ' + code + ' fetching ' + externalEntity + ' ' + qboId + '.'
                );
            }

            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> entityData  = (Map<String, Object>) responseMap.get(externalEntity);
            if (entityData == null) {
                throw new AuraHandledException('QBO response did not contain ' + externalEntity + ' data.');
            }

            Map<String, String> mapping = resolveInboundMapping(externalEntity, objectApiName);
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
            SObject record = sot.newSObject(recordId);
            applyMapping(record, entityData, mapping);
            record.put(resolved.qboIdField, qboId);

            QBTriggerHandler.isAccountProcessing = true;
            QBTriggerHandler.isOrderProcessing   = true;
            try {
                update record;
            } finally {
                QBTriggerHandler.isAccountProcessing = false;
                QBTriggerHandler.isOrderProcessing   = false;
            }

            return new ActionResponse(true, externalEntity + ' ' + qboId + ' synced from QBO.');

        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            logException('syncFromQbo', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        } catch (AuraHandledException e) {
            logException('syncFromQbo', e, objectApiName, recordId);
            throw e;
        } catch (Exception e) {
            logException('syncFromQbo', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── PDF download ──────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Map<String, String> downloadPdf(Id recordId, String objectApiName) {
        try {
            QBOInvoiceMappingResolver.ResolverResult resolved = QBOInvoiceMappingResolver.resolve();
            assertObjectMatch(objectApiName, resolved.invoiceSourceObject);

            if (String.isBlank(resolved.qboIdField)) {
                throw new AuraHandledException(
                    'No QBO Invoice Id field mapping found. Configure a QBO to SF mapping for the Invoice Id field.'
                );
            }

            String qboId = fetchFieldValue(recordId, objectApiName, resolved.qboIdField);
            if (String.isBlank(qboId)) {
                throw new AuraHandledException(
                    'This record has not been synced to QBO yet. Sync it to QBO before downloading the PDF.'
                );
            }

            String displayName = fetchFieldValue(recordId, objectApiName, resolved.displayNameField);

            // Check if record is a Draft Order mapped to an Estimate
            String stripped = stripNamespace(objectApiName);
            if (stripped.equalsIgnoreCase('Order')) {
                String status = fetchFieldValue(recordId, objectApiName, 'Status');
                Boolean mapDraftAsEstimates = false;
                try {
                    mapDraftAsEstimates = ConnectorConfigResolver.getBoolean('qbo', 'Map_Draft_Orders_as_Estimates__c');
                } catch (Exception e) {}

                if (status == 'Draft' && mapDraftAsEstimates) {
                    throw new AuraHandledException(
                        'This QuickBooks ID (' + qboId + ') is for an Estimate, not an Invoice. Please activate the Order and sync it as an Invoice before downloading the Invoice PDF.'
                    );
                }
            }

            HttpResponse res = QuickBooksAuthHandler.makeBinaryApiCall('/invoice/' + qboId + '/pdf');

            if (res.getStatusCode() == 400 || res.getStatusCode() == 404) {
                // Check if this ID belongs to an Estimate in QBO
                HttpResponse estCheck = QuickBooksAuthHandler.makeBinaryApiCall('/estimate/' + qboId + '/pdf');
                if (estCheck != null && estCheck.getStatusCode() == 200) {
                    throw new AuraHandledException(
                        'This QuickBooks ID (' + qboId + ') is for an Estimate, not an Invoice. Please activate the Order and sync it as an Invoice before downloading the Invoice PDF.'
                    );
                }
            }

            if (res.getStatusCode() != 200) {
                throw new AuraHandledException(
                    'QBO returned HTTP ' + res.getStatusCode() + ' when fetching the invoice PDF. ' +
                    'Verify the QBO connection and invoice status.'
                );
            }

            Blob pdfBlob = res.getBodyAsBlob();
            if (pdfBlob == null || pdfBlob.size() == 0) {
                throw new AuraHandledException('QBO returned an empty PDF body. Please try again.');
            }

            String fileTitle = 'QBO Invoice PDF'
                + (String.isNotBlank(displayName) ? ' - ' + displayName : '')
                + ' (' + qboId + ')';
            String contentDocumentId = savePdf(recordId, pdfBlob, fileTitle);

            Map<String, String> result = new Map<String, String>();
            result.put('contentDocumentId', contentDocumentId);
            result.put('message', 'PDF saved successfully.');
            return result;

        } catch (QBOInvoiceMappingResolver.ResolverException e) {
            logException('downloadPdf', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        } catch (AuraHandledException e) {
            logException('downloadPdf', e, objectApiName, recordId);
            throw e;
        } catch (Exception e) {
            logException('downloadPdf', e, objectApiName, recordId);
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    @TestVisible
    private static Map<String, String> resolveInboundMapping(String externalEntity, String objectApiName) {
        if (externalEntity == 'Customer') {
            return QBObjectMappings.getCustomerToAccountMapping();
        }
        // For Invoice entities: use the object-specific inbound mapping
        if (stripNamespace(objectApiName).equalsIgnoreCase('order')) {
            return QBObjectMappings.getInvoiceToOrderMapping();
        }
        return QBObjectMappings.reverseMapping(QBObjectMappings.getInvoiceMapping());
    }

    @TestVisible
    private static void applyMapping(SObject record, Map<String, Object> data, Map<String, String> mapping) {
        if (mapping == null || mapping.isEmpty()) return;
        for (String qboPath : mapping.keySet()) {
            String sfField = mapping.get(qboPath);
            if (String.isBlank(sfField)) continue;
            Object val = getNestedValue(data, qboPath);
            if (val != null) {
                try {
                    if (val instanceof String && ((String)val).length() == 10 && ((String)val).contains('-')) {
                        record.put(sfField, Date.valueOf((String)val));
                    } else {
                        record.put(sfField, val);
                    }
                } catch (Exception ignored) {}
            }
        }
    }

    @TestVisible
    private static Object getNestedValue(Map<String, Object> data, String path) {
        if (String.isBlank(path) || data == null) return null;
        if (!path.contains('.')) return data.get(path);
        List<String> keys = path.split('\\.');
        Map<String, Object> cur = data;
        for (Integer i = 0; i < keys.size() - 1; i++) {
            Object next = cur.get(keys[i]);
            if (!(next instanceof Map<String, Object>)) return null;
            cur = (Map<String, Object>) next;
        }
        return cur.get(keys[keys.size() - 1]);
    }

    @TestVisible
    private static String fetchFieldValue(Id recordId, String objectApiName, String fieldApiName) {
        if (String.isBlank(fieldApiName)) return null;
        try {
            String query = 'SELECT ' + fieldApiName + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.query(query);
            if (records.isEmpty()) return null;
            Object val = records[0].get(fieldApiName);
            return val == null ? null : String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String savePdf(Id recordId, Blob pdfBlob, String fileTitle) {
        String safeTitle   = fileTitle.replaceAll('[^A-Za-z0-9_ \\-()]', '');
        String pathOnClient = safeTitle.replaceAll('[ ()]', '_') + '.pdf';

        List<ContentDocumentLink> existing = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocument.Title = :safeTitle
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            String existingDocId = existing[0].ContentDocumentId;
            insert new ContentVersion(
                Title             = safeTitle,
                PathOnClient      = pathOnClient,
                VersionData       = pdfBlob,
                ContentDocumentId = existingDocId
            );
            return existingDocId;
        }

        ContentVersion cv = new ContentVersion(
            Title        = safeTitle,
            PathOnClient = pathOnClient,
            VersionData  = pdfBlob,
            Origin       = 'H'
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = recordId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        return cv.ContentDocumentId;
    }

    private static void assertObjectMatch(String objectApiName, String configuredObject) {
        if (!objectMatches(objectApiName, configuredObject)) {
            throw new AuraHandledException(
                'This action is only available on the QBO Invoice source object (' +
                configuredObject + '). This record is a ' + objectApiName + '.'
            );
        }
    }

    private static Boolean objectMatches(String objectApiName, String configuredObject) {
        return stripNamespace(objectApiName).equalsIgnoreCase(stripNamespace(configuredObject));
    }

    private static String stripNamespace(String name) {
        if (String.isBlank(name)) return '';
        if (name.endsWith('__c') && name.indexOf('__') != name.lastIndexOf('__')) {
            return name.substringAfter('__');
        }
        return name;
    }

    private static void logException(String methodName, Exception e, String objectApiName, Id recordId) {
        ErrorLogUtility.LogContext ctx = new ErrorLogUtility.LogContext();
        ctx.gatewayName         = 'QuickBooks';
        ctx.classMethodName     = 'QBOInvoicePdfActionController.' + methodName;
        ctx.errorMessage        = e.getTypeName() + ': ' + e.getMessage();
        ctx.stackTrace          = e.getStackTraceString();
        ctx.sourceObjectApiName = objectApiName;
        ctx.sourceRecordId      = recordId;
        ctx.sourceRecordIdText  = recordId == null ? null : String.valueOf(recordId);
        ctx.errorCategory       = 'Code Exception';
        ErrorLogUtility.logError(ctx);
    }
}