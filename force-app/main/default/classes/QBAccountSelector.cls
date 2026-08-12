public inherited sharing class QBAccountSelector {
    public static Account selectForOutbound(Id accountId) {
        if (accountId == null) {
            throw new SelectorException('Account Id is required.');
        }

        List<Account> records = selectForOutbound(new Set<Id>{ accountId });
        if (records.isEmpty()) {
            throw new SelectorException('Account not found: ' + accountId);
        }
        return records[0];
    }

    public static List<Account> selectForOutbound(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        Set<String> requestedFields = new Set<String>{
            'Id', 'Name', 'QuickbookID__c', 'RecordTypeId'
        };
        requestedFields.addAll(QBObjectMappings.getAccountToCustomerMapping().keySet());
        requestedFields.addAll(QBObjectMappings.getAccountToVendorMapping().keySet());
        requestedFields.addAll(new Set<String>{
            'IsPersonAccount', 'FirstName', 'MiddleName', 'LastName', 'Suffix', 'PersonEmail'
        });

        Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
        Set<String> queryFields = new Set<String>();
        for (String requestedField : requestedFields) {
            if (String.isBlank(requestedField) || requestedField.contains('.')) {
                continue;
            }
            Schema.SObjectField token = findField(accountFields, requestedField);
            if (token != null && token.getDescribe().isAccessible()) {
                queryFields.add(token.getDescribe().getName());
            }
        }

        List<String> sortedFields = new List<String>(queryFields);
        sortedFields.sort();
        return Database.query(
            'SELECT ' + String.join(sortedFields, ',') +
            ' FROM Account WHERE Id IN :accountIds'
        );
    }

    private static Schema.SObjectField findField(
        Map<String, Schema.SObjectField> fields,
        String fieldName
    ) {
        Schema.SObjectField token = fields.get(fieldName.toLowerCase());
        if (token != null) {
            return token;
        }
        if (!fieldName.contains('__')) {
            return null;
        }
        for (String availableName : fields.keySet()) {
            if (
                availableName.equalsIgnoreCase(fieldName) ||
                availableName.toLowerCase().endsWith('__' + fieldName.toLowerCase())
            ) {
                return fields.get(availableName);
            }
        }
        return null;
    }

    public class SelectorException extends Exception {}
}
