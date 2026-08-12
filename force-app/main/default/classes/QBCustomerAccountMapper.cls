public inherited sharing class QBCustomerAccountMapper {
    public static Boolean shouldCreatePersonAccount(
        Map<String, Object> customerData
    ) {
        if (customerData == null || String.isNotBlank(stringValue(customerData.get('CompanyName')))) {
            return false;
        }
        return String.isNotBlank(stringValue(customerData.get('GivenName'))) ||
            String.isNotBlank(stringValue(customerData.get('FamilyName')));
    }

    public static void applyCustomer(
        Account accountRecord,
        Map<String, Object> customerData,
        Map<String, String> inboundMapping,
        Id personAccountRecordTypeId
    ) {
        if (accountRecord == null || customerData == null) {
            return;
        }

        Boolean isPersonAccount = personAccountRecordTypeId != null &&
            accountRecord.RecordTypeId == personAccountRecordTypeId;
        Boolean nameSyncEnabled = false;

        if (inboundMapping != null) {
            for (String quickBooksField : inboundMapping.keySet()) {
                String salesforceField = inboundMapping.get(quickBooksField);
                Object quickBooksValue = getNestedValue(customerData, quickBooksField);
                if (salesforceField == 'Name') {
                    nameSyncEnabled = true;
                    if (isPersonAccount) {
                        continue;
                    }
                }
                putFieldValue(accountRecord, salesforceField, quickBooksValue, isPersonAccount);
            }
        }

        if (isPersonAccount && nameSyncEnabled) {
            applyStructuredPersonName(accountRecord, customerData);
        }

        if (!isPersonAccount && accountRecord.Id == null && String.isBlank(accountRecord.Name)) {
            String fallbackName = firstNonBlank(
                stringValue(customerData.get('DisplayName')),
                stringValue(customerData.get('CompanyName')),
                stringValue(customerData.get('FullyQualifiedName'))
            );
            if (String.isNotBlank(fallbackName)) {
                accountRecord.Name = fallbackName;
            }
        }
    }

    private static void applyStructuredPersonName(
        Account accountRecord,
        Map<String, Object> customerData
    ) {
        String givenName = stringValue(customerData.get('GivenName'));
        String middleName = stringValue(customerData.get('MiddleName'));
        String familyName = stringValue(customerData.get('FamilyName'));
        String suffix = stringValue(customerData.get('Suffix'));

        if (String.isNotBlank(familyName)) {
            putFieldValue(accountRecord, 'LastName', familyName, true);
            if (String.isNotBlank(givenName)) {
                putFieldValue(accountRecord, 'FirstName', givenName, true);
            }
        } else if (accountRecord.Id == null && String.isNotBlank(givenName)) {
            putFieldValue(accountRecord, 'LastName', givenName, true);
        } else if (String.isNotBlank(givenName)) {
            putFieldValue(accountRecord, 'FirstName', givenName, true);
        }
        if (String.isNotBlank(middleName)) {
            putFieldValue(accountRecord, 'MiddleName', middleName, true);
        }
        if (String.isNotBlank(suffix)) {
            putFieldValue(accountRecord, 'Suffix', suffix, true);
        }
    }

    private static void putFieldValue(
        Account accountRecord,
        String fieldName,
        Object value,
        Boolean isPersonAccount
    ) {
        if (
            accountRecord == null ||
            String.isBlank(fieldName) ||
            fieldName.contains('.') ||
            value == null
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
        Schema.SObjectField fieldToken = fields.get(fieldName.toLowerCase());
        if (fieldToken == null) {
            fieldToken = fields.get(('QuickBridgeTLG__' + fieldName).toLowerCase());
        }
        if (fieldToken == null) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        Boolean allowedByOperation = accountRecord.Id == null
            ? fieldDescribe.isCreateable()
            : fieldDescribe.isUpdateable();
        if (!allowedByOperation) {
            return;
        }

        String resolvedFieldName = fieldDescribe.getName();
        if (isPersonOnlyField(resolvedFieldName) && !isPersonAccount) {
            return;
        }
        if (resolvedFieldName == 'Name' && isPersonAccount) {
            return;
        }

        accountRecord.put(
            resolvedFieldName,
            coerceValue(value, fieldDescribe.getType())
        );
    }

    private static Boolean isPersonOnlyField(String fieldName) {
        return String.isNotBlank(fieldName) &&
            (fieldName.startsWith('Person') ||
            fieldName == 'FirstName' ||
            fieldName == 'MiddleName' ||
            fieldName == 'LastName' ||
            fieldName == 'Suffix' ||
            fieldName.endsWith('__pc'));
    }

    private static Object coerceValue(
        Object value,
        Schema.DisplayType displayType
    ) {
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
            if (displayType == Schema.DisplayType.Date) {
                return Date.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.DateTime) {
                return Datetime.valueOf(String.valueOf(value));
            }
            if (displayType == Schema.DisplayType.Boolean) {
                return value instanceof Boolean
                    ? value
                    : Boolean.valueOf(String.valueOf(value));
            }
        } catch (Exception ignored) {
            return value;
        }
        return value;
    }

    private static Object getNestedValue(
        Map<String, Object> data,
        String path
    ) {
        if (data == null || String.isBlank(path)) {
            return null;
        }
        Object current = data;
        for (String part : path.split('\\.')) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>) current).get(part);
        }
        return current;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static String firstNonBlank(String first, String second, String third) {
        if (String.isNotBlank(first)) {
            return first;
        }
        if (String.isNotBlank(second)) {
            return second;
        }
        return third;
    }
}
