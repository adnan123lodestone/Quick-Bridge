@IsTest
private class ErrorLogLinkBackfillServiceTest {
    @IsTest
    static void backfillMissingLinksIsIdempotent() {
        Account accountRecord = new Account(Name = 'Backfill Source Account');
        insert accountRecord;

        Contact contactRecord = new Contact(
            LastName = 'Backfill Action Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Error_Log__c sourceAndActionLog = new Error_Log__c(
            Gateway_Name__c = 'Payment',
            Class_Method_Name__c = 'BackfillTest.sourceAndAction',
            Error_Message__c = 'Legacy log with source and action fields.',
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(accountRecord.Id),
            Action_Source_Object__c = 'Contact',
            Action_Source_Record_Id__c = String.valueOf(contactRecord.Id)
        );
        Error_Log__c sourceOnlyLog = new Error_Log__c(
            Gateway_Name__c = 'Payment',
            Class_Method_Name__c = 'BackfillTest.sourceOnly',
            Error_Message__c = 'Legacy log with only source fields.',
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(accountRecord.Id)
        );
        insert new List<Error_Log__c>{ sourceAndActionLog, sourceOnlyLog };

        Test.startTest();
        ErrorLogLinkBackfillService.BackfillResult firstRun = ErrorLogLinkBackfillService.backfillMissingLinks(100);
        ErrorLogLinkBackfillService.BackfillResult secondRun = ErrorLogLinkBackfillService.backfillMissingLinks(100);
        Test.stopTest();

        System.assertEquals(2, firstRun.scanned);
        System.assertEquals(3, firstRun.inserted);
        System.assertEquals(0, firstRun.failed);
        System.assertEquals(2, secondRun.scanned);
        System.assertEquals(0, secondRun.inserted);
        System.assertEquals(3, secondRun.skipped);

        String accountIdText = String.valueOf(accountRecord.Id);
        String contactIdText = String.valueOf(contactRecord.Id);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Error_Log_Link__c
                WHERE
                    Linked_Object_API_Name__c = 'Account'
                    AND Linked_Record_Id__c = :accountIdText
                    AND Relationship_Role__c = 'Source'
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Error_Log_Link__c
                WHERE
                    Linked_Object_API_Name__c = 'Contact'
                    AND Linked_Record_Id__c = :contactIdText
                    AND Relationship_Role__c = 'Action Source'
            ]
        );
    }
}
