public class QBVendorToAccountSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {

    private String lastSyncDate;
    private ConnectorExecutionResult sharedExecutionResult;
    private Set<String> sharedFailedReferences = new Set<String>();

    public QBVendorToAccountSyncBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('yyyy-MM-dd');
    }

    public QBVendorToAccountSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
    }

    public ConnectorExecutionResult executeSharedScope(List<String> scope) {
        sharedExecutionResult = ConnectorExecutionResult.success();
        sharedFailedReferences.clear();
        Integer submittedCount = scope == null ? 0 : scope.size();
        execute(null, scope);
        sharedExecutionResult.processedCount = submittedCount;
        sharedExecutionResult.failedCount = Math.min(submittedCount, sharedFailedReferences.size());
        sharedExecutionResult.successfulCount = Math.max(0, submittedCount - sharedExecutionResult.failedCount);
        ConnectorExecutionResult result = sharedExecutionResult;
        sharedExecutionResult = null;
        return result;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> vendorPayloads = new List<String>();

        try {
            vendorPayloads = QuickBooksBulkQueryService.serializeRecords(
                QuickBooksBulkQueryService.queryUpdatedSince('Vendor', lastSyncDate)
            );
        } catch (Exception e) {
            System.debug('Error querying QuickBooks vendors: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBVendorToAccountSyncBatch.start',
                e,
                null,
                null
            );
        }

        return vendorPayloads;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        QBTriggerHandler.isAccountProcessing = true;

        try {
            List<Account> accountsToUpsert = new List<Account>();
            Id vendorRecordTypeId = getVendorAccountRecordTypeId();

            for (String vendorPayload : scope) {
                String vendorId = getExternalIdFromPayload(vendorPayload);
                try {
                    Map<String, Object> vendorData = resolveVendorData(vendorPayload);

                    if (vendorData != null) {
                        Account accountToSync = processVendorData(vendorData, vendorRecordTypeId);

                        if (accountToSync != null) {
                            accountsToUpsert.add(accountToSync);
                        } else {
                            recordSharedFailure(vendorId, 'QuickBooks vendor did not produce an Account record.');
                        }
                    } else {
                        recordSharedFailure(vendorId, 'QuickBooks vendor payload was blank or malformed.');
                    }
                } catch (Exception e) {
                    System.debug('Error processing vendor ' + vendorId + ': ' + e.getMessage());
                    ErrorLogUtility.LogContext context = new ErrorLogUtility.LogContext();
                    context.gatewayName = 'QuickBooks';
                    context.classMethodName = 'QBVendorToAccountSyncBatch.execute.processVendor';
                    context.errorMessage = e.getTypeName() + ': ' + e.getMessage();
                    context.stackTrace = e.getStackTraceString();
                    context.sourceObjectApiName = 'Account';
                    context.sourceRecordIdText = vendorId;
                    context.errorCategory = 'Code Exception';
                    context.externalReference = vendorId;
                    ErrorLogUtility.logError(context);
                    recordSharedFailure(
                        vendorId,
                        e.getMessage(),
                        ConnectorInboundOperationExecutor.isRetryableException(e)
                    );
                }
            }

            if (!accountsToUpsert.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(accountsToUpsert, Account.QuickbookID__c, false);
                ErrorLogUtility.logUpsertResults(
                    'QuickBooks',
                    'QBVendorToAccountSyncBatch.execute.upsertAccounts',
                    'upsert',
                    accountsToUpsert,
                    results,
                    null,
                    null
                );
                Integer successCount = 0;
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                    } else {
                        Database.Error firstError = results[i].getErrors()[0];
                        recordSharedFailure(
                            accountsToUpsert[i].QuickbookID__c,
                            firstError.getStatusCode() + ': ' + firstError.getMessage()
                        );
                    }
                }
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', successCount);
            }
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    private void recordSharedFailure(String externalReference, String message) {
        recordSharedFailure(externalReference, message, false);
    }

    private void recordSharedFailure(String externalReference, String message, Boolean retryable) {
        if (sharedExecutionResult == null) {
            return;
        }
        sharedFailedReferences.add(
            String.isBlank(externalReference)
                ? 'anonymous-' + String.valueOf(sharedFailedReferences.size())
                : externalReference
        );
        sharedExecutionResult.addError(message);
        if (retryable == true) {
            sharedExecutionResult.retryable = true;
            sharedExecutionResult.retryDelaySeconds = 60;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('QBVendorToAccountSyncBatch completed');
    }

    private Map<String, Object> resolveVendorData(String vendorPayload) {
        if (String.isBlank(vendorPayload)) {
            return null;
        }

        try {
            Object parsed = JSON.deserializeUntyped(vendorPayload);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>)parsed;
            }
        } catch (Exception e) {
            // Legacy payloads were raw QuickBooks ids; hydrate only those compatibility inputs.
        }

        // Scheduled/batch execution must receive hydrated payloads from start().
        // Single-record hydration remains in syncVendorFromQBO().
        return null;
    }

    private String getExternalIdFromPayload(String vendorPayload) {
        Map<String, Object> vendorData = resolveSerializedPayload(vendorPayload);
        return vendorData == null ? vendorPayload : String.valueOf(vendorData.get('Id'));
    }

    private Map<String, Object> resolveSerializedPayload(String payload) {
        if (String.isBlank(payload)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(payload);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>)parsed : null;
        } catch (Exception e) {
            return null;
        }
    }

    private Account processVendorData(Map<String, Object> vendorData, Id vendorRecordTypeId) {
        String qbId = (String)vendorData.get('Id');

        List<Account> existingAccounts = [SELECT Id, QuickbookID__c FROM Account WHERE QuickbookID__c = :qbId LIMIT 1];

        Account account;
        if (!existingAccounts.isEmpty()) {
            account = existingAccounts[0];
        } else {
            account = new Account();
        }

        account.Is_Synced__c = true;
        if (vendorRecordTypeId != null) {
            account.RecordTypeId = vendorRecordTypeId;
        }

        Map<String, String> mapping = QBObjectMappings.getVendorToAccountMapping();

        for (String qbField : mapping.keySet()) {
            String sfField = mapping.get(qbField);
            Object qbValue = getNestedValue(vendorData, qbField);

            if (qbValue != null) {
                try {
                    putFieldValue(account, sfField, qbValue);
                } catch(Exception e) {}
            }
        }

        if (String.isBlank(account.Name)) {
            account.Name = getVendorAccountName(vendorData);
        }

        account.QuickbookID__c = qbId;

        return account;
    }

    private Id getVendorAccountRecordTypeId() {
        List<RecordType> vendorRecordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
            AND IsActive = true
            AND (Name = 'Vendor' OR DeveloperName = 'Vendor')
            LIMIT 1
        ];

        return vendorRecordTypes.isEmpty() ? null : vendorRecordTypes[0].Id;
    }

    private String getVendorAccountName(Map<String, Object> vendorData) {
        String displayName = (String)vendorData.get('DisplayName');
        if (String.isNotBlank(displayName)) {
            return displayName;
        }

        String companyName = (String)vendorData.get('CompanyName');
        if (String.isNotBlank(companyName)) {
            return companyName;
        }

        String printOnCheckName = (String)vendorData.get('PrintOnCheckName');
        if (String.isNotBlank(printOnCheckName)) {
            return printOnCheckName;
        }

        String givenName = (String)vendorData.get('GivenName');
        String familyName = (String)vendorData.get('FamilyName');
        String fullName = String.join(new List<String>{
            String.isBlank(givenName) ? '' : givenName,
            String.isBlank(familyName) ? '' : familyName
        }, ' ').trim();

        return String.isBlank(fullName) ? 'Unknown Vendor' : fullName;
    }

    private Object getNestedValue(Map<String, Object> data, String path) {
        String[] pathParts = path.split('\\.');
        Object current = data;

        for (String part : pathParts) {
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>)current).get(part);
            } else {
                return null;
            }
        }
        return current;
    }

    private void putFieldValue(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName) || fieldName.contains('.') || value == null) {
            return;
        }

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (!fields.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
        if (!fieldDescribe.isCreateable() && !fieldDescribe.isUpdateable()) {
            return;
        }

        Schema.DisplayType displayType = fieldDescribe.getType();
        record.put(fieldName, coerceValue(value, displayType));
    }

    private Object coerceValue(Object value, Schema.DisplayType displayType) {
        if (value == null) {
            return null;
        }

        try {
            if (
                displayType == Schema.DisplayType.Currency ||
                displayType == Schema.DisplayType.Double ||
                displayType == Schema.DisplayType.Percent
            ) {
                return Decimal.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Integer) {
                return Integer.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Boolean) {
                if (value instanceof Boolean) {
                    return value;
                }
                return String.valueOf(value).toLowerCase() == 'true';
            }
            if (displayType == Schema.DisplayType.Date) {
                if (value instanceof Date) {
                    return value;
                }
                return Date.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.DateTime) {
                if (value instanceof Datetime) {
                    return value;
                }
                return Datetime.valueOf(String.valueOf(value));
            }
        } catch (Exception e) {
            return value;
        }

        return value;
    }

    public void syncVendorFromQBO(String vendorId) {
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', '/vendor/' + vendorId, null);
        if (res.getStatusCode() == 200) {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> vendorData = (Map<String, Object>) resp.get('Vendor');
            Account acc = processVendorData(vendorData, getVendorAccountRecordTypeId()); 
            upsert acc Account.QuickbookID__c;
        } else {
            throw new CalloutException('Unable to fetch vendor from QBO: ' + res.getBody());
        }
    }
}
