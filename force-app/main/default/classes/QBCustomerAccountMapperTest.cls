@IsTest(IsParallel=false)
private class QBCustomerAccountMapperTest {
    @IsTest
    static void existingPersonUsesStructuredNamesAndNeverName() {
        Id personRecordTypeId = getPersonRecordTypeId();
        if (personRecordTypeId == null) {
            return;
        }
        QBTriggerHandler.isAccountProcessing = true;
        Account person = new Account(
            RecordTypeId = personRecordTypeId,
            FirstName = 'Before',
            LastName = 'Person'
        );
        insert person;
        QBTriggerHandler.isAccountProcessing = false;

        Account updateRecord = new Account(Id = person.Id, RecordTypeId = personRecordTypeId);
        QBCustomerAccountMapper.applyCustomer(
            updateRecord,
            new Map<String, Object>{
                'DisplayName' => 'Ignored Composite Name',
                'GivenName' => 'After',
                'MiddleName' => 'Q',
                'FamilyName' => 'Customer',
                'Suffix' => 'Jr.'
            },
            new Map<String, String>{ 'DisplayName' => 'Name' },
            personRecordTypeId
        );

        System.assertEquals(false, updateRecord.getPopulatedFieldsAsMap().containsKey('Name'));
        update updateRecord;
        Account refreshed = [SELECT FirstName, LastName FROM Account WHERE Id = :person.Id];
        System.assertEquals('After', refreshed.FirstName);
        System.assertEquals('Customer', refreshed.LastName);
        if (Schema.SObjectType.Account.fields.getMap().containsKey('MiddleName')) {
            System.assertEquals('Q', updateRecord.get('MiddleName'));
        }
        if (Schema.SObjectType.Account.fields.getMap().containsKey('Suffix')) {
            System.assertEquals('Jr.', updateRecord.get('Suffix'));
        }
    }

    @IsTest
    static void displayNameOnlyDoesNotOverwritePersonStructuredName() {
        Id personRecordTypeId = getPersonRecordTypeId();
        if (personRecordTypeId == null) {
            return;
        }
        Account updateRecord = new Account(
            Id = (Id) (Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001'),
            RecordTypeId = personRecordTypeId
        );
        QBCustomerAccountMapper.applyCustomer(
            updateRecord,
            new Map<String, Object>{ 'DisplayName' => 'Do Not Split This' },
            new Map<String, String>{ 'DisplayName' => 'Name' },
            personRecordTypeId
        );
        Map<String, Object> populated = updateRecord.getPopulatedFieldsAsMap();
        System.assertEquals(false, populated.containsKey('Name'));
        System.assertEquals(false, populated.containsKey('FirstName'));
        System.assertEquals(false, populated.containsKey('LastName'));
    }

    @IsTest
    static void businessNameAndNewPersonClassificationRemainExplicit() {
        Account business = new Account();
        QBCustomerAccountMapper.applyCustomer(
            business,
            new Map<String, Object>{ 'DisplayName' => 'Mapped Business' },
            new Map<String, String>{ 'DisplayName' => 'Name' },
            getPersonRecordTypeId()
        );
        System.assertEquals('Mapped Business', business.Name);
        System.assertEquals(
            true,
            QBCustomerAccountMapper.shouldCreatePersonAccount(
                new Map<String, Object>{ 'GivenName' => 'Structured' }
            )
        );
        System.assertEquals(
            false,
            QBCustomerAccountMapper.shouldCreatePersonAccount(
                new Map<String, Object>{ 'DisplayName' => 'Display Only' }
            )
        );
        System.assertEquals(
            false,
            QBCustomerAccountMapper.shouldCreatePersonAccount(
                new Map<String, Object>{ 'CompanyName' => 'Company', 'GivenName' => 'Owner' }
            )
        );
    }

    private static Id getPersonRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }
}
