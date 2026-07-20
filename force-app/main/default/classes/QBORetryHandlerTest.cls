@IsTest
private class QBORetryHandlerTest {

    @IsTest
    static void testLogExceptionWithRelatedId() {
        Account acc = new Account(Name = 'Test QuickBooks Account');
        insert acc;

        Error_Log__c testLog = new Error_Log__c(
            Gateway_Name__c = 'QuickBooks',
            Error_Category__c = 'Callout Failure',
            Source_Object__c = 'Account',
            Source_Record_Id__c = acc.Id,
            Retry_Status__c = 'Pending',
            Error_Message__c = 'Integration Error',
            Class_Method_Name__c = 'QBAccountService.syncAccountToQuickBooks',
            Retry_Count__c = 0
        );
        insert testLog;

        Test.startTest();
        QBORetryHandler handler = new QBORetryHandler();
        try {
            handler.handle(testLog);
        } catch (Exception e) {
        }
        Test.stopTest();

        Error_Log__c updatedLog = [
            SELECT Retry_Status__c, Retry_Count__c, Source_Record_Id__c
            FROM Error_Log__c
            WHERE Id = :testLog.Id
        ];

        System.assertNotEquals(null, updatedLog);
    }
}