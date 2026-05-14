public class QBVendorToAccountSyncBatch implements Database.Batchable<String>, Database.AllowsCallouts {

    private String lastSyncDate;

    public QBVendorToAccountSyncBatch() {
        Datetime yesterday = Datetime.now().addDays(-1);
        this.lastSyncDate = yesterday.format('yyyy-MM-dd');
    }

    public QBVendorToAccountSyncBatch(String syncDate) {
        this.lastSyncDate = syncDate;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> vendorIdsList = new List<String>();

        try {
            String query = 'select * from Vendor Where Metadata.LastUpdatedTime > \'' + lastSyncDate + '\'';
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
            String resourcePath = '/query?query=' + encodedQuery + '&minorversion=65';

            HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', resourcePath, null);

            if (response != null && response.getStatusCode() == 200 && String.isNotBlank(response.getBody())) {
                Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());

                if (responseMap != null && responseMap.containsKey('QueryResponse')) {
                    Map<String, Object> queryResponse = (Map<String, Object>)responseMap.get('QueryResponse');

                    if (queryResponse != null && queryResponse.containsKey('Vendor')) {
                        List<Object> vendors = (List<Object>)queryResponse.get('Vendor');
                        if (vendors != null) {
                            for (Object vendorObj : vendors) {
                                if (vendorObj != null) {
                                    Map<String, Object> vendor = (Map<String, Object>)vendorObj;
                                    if (vendor.containsKey('Id')) {
                                        vendorIdsList.add((String)vendor.get('Id'));
                                    }
                                }
                            }
                        }
                    }
                }
            }
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

        return vendorIdsList;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        IntegrationUsageService.assertCanConsumeTask('QuickBooks', scope == null ? 1 : scope.size());
        QBTriggerHandler.isAccountProcessing = true;

        try {
            List<Account> accountsToUpsert = new List<Account>();
            Id vendorRecordTypeId = getVendorAccountRecordTypeId();

            for (String vendorId : scope) {
                try {
                    HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', '/vendor/' + vendorId, null);

                    if (response.getStatusCode() == 200) {
                        Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                        Map<String, Object> vendorData = (Map<String, Object>)responseMap.get('Vendor');

                        if (vendorData != null) {
                            Account accountToSync = processVendorData(vendorData, vendorRecordTypeId);

                            if (accountToSync != null) {
                                accountsToUpsert.add(accountToSync);
                            }
                        }
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
                for (Database.UpsertResult result : results) {
                    if (result.isSuccess()) {
                        successCount++;
                    }
                }
                IntegrationUsageService.recordSuccessfulRecordSync('QuickBooks', successCount);
            }
        } finally {
            QBTriggerHandler.isAccountProcessing = false;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('QBVendorToAccountSyncBatch completed');
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
}