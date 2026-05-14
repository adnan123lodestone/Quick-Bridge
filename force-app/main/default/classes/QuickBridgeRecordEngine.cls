public with sharing class QuickBridgeRecordEngine {
    @TestVisible private static List<Invoice_Field_Mapping__mdt> testActiveMappings;

    public static void processIncomingInvoice(Map<String, Object> incomingData) {
        try {
            Invoice__c standardInvoice = new Invoice__c();

            if(incomingData.containsKey('Amount__c')) {
                standardInvoice.Amount__c = (Decimal)incomingData.get('Amount__c');
            }
            if(incomingData.containsKey('Order__c')) {
                standardInvoice.Order__c = (Id)incomingData.get('Order__c');
            }
            if(incomingData.containsKey('Related_Account__c')) {
                standardInvoice.Related_Account__c = (Id)incomingData.get('Related_Account__c');
            }
            if(incomingData.containsKey('Reference_number__c')) {
                standardInvoice.Reference_number__c = (String)incomingData.get('Reference_number__c');
            }
            standardInvoice.Status__c = 'Paid';
            standardInvoice.Invoice_Date__c = Date.today();

            insert standardInvoice;
            System.debug('QuickBridge Invoice Created: ' + standardInvoice.Id);

            checkAndCreateClientMappedRecord(incomingData, standardInvoice.Id);

        } catch (Exception e) {
            System.debug('QuickBridge Engine Error: ' + e.getMessage());
            Id orderId = getIdValue(incomingData, 'Order__c');
            Id accountId = getIdValue(incomingData, 'Related_Account__c');
            if (orderId != null) {
                ErrorLogUtility.logException('Payment', 'QuickBridgeRecordEngine.processIncomingInvoice', e, 'Order', orderId);
            } else if (accountId != null) {
                ErrorLogUtility.logException('Payment', 'QuickBridgeRecordEngine.processIncomingInvoice', e, 'Account', accountId);
            } else {
                ErrorLogUtility.logException('Payment', 'QuickBridgeRecordEngine.processIncomingInvoice', e, null, null);
            }
        }
    }

    private static void checkAndCreateClientMappedRecord(Map<String, Object> incomingData, Id standardInvoiceId) {
        List<Invoice_Field_Mapping__mdt> activeMappings = Test.isRunningTest() && testActiveMappings != null
            ? testActiveMappings
            : [
                SELECT Target_Object_API_Name__c, Source_Field_API_Name__c, Target_Field_API_Name__c
                FROM Invoice_Field_Mapping__mdt
                WHERE Is_Active__c = true
            ];

        if (!activeMappings.isEmpty()) {
            String targetObjName = activeMappings[0].Target_Object_API_Name__c;
            SObjectType customObjType = Schema.getGlobalDescribe().get(targetObjName);

            if (customObjType != null) {
                SObject clientRecord = customObjType.newSObject();
                for (Invoice_Field_Mapping__mdt m : activeMappings) {
                    if (incomingData.containsKey(m.Source_Field_API_Name__c)) {
                        clientRecord.put(m.Target_Field_API_Name__c, incomingData.get(m.Source_Field_API_Name__c));
                    }
                }
                try {
                    insert clientRecord;
                    System.debug('Client Specific Record Created: ' + clientRecord.Id);
                } catch (Exception e) {
                    // Use dynamic target object name for the failed record
                    // Action source remains Invoice__c since that's what triggered this
                    ErrorLogUtility.logDmlFailure(
                        'Payment',
                        'QuickBridgeRecordEngine.checkAndCreateClientMappedRecord',
                        'insert',
                        targetObjName,
                        null, // clientRecord.Id would be null on insert failure
                        e.getTypeName() + ': ' + e.getMessage(),
                        'Invoice__c',
                        standardInvoiceId
                    );
                }
            }
        }
    }

    private static Id getIdValue(Map<String, Object> incomingData, String key) {
        if (incomingData == null || String.isBlank(key) || !incomingData.containsKey(key) || incomingData.get(key) == null) {
            return null;
        }
        try {
            return (Id) incomingData.get(key);
        } catch (Exception e) {
            try {
                return (Id) String.valueOf(incomingData.get(key));
            } catch (Exception ignored) {
                return null;
            }
        }
    }
}