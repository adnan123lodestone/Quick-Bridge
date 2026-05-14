@isTest
public class TriggerCoverageTest {
    @isTest
    static void testTriggers() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Credit_Memo__c cm = new Credit_Memo__c(); 
        insert cm;

        Purchase_Order__c po = new Purchase_Order__c(Account__c = acc.Id);
        insert po;
    }
}