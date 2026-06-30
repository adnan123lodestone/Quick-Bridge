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

        Invoice__c inv = new Invoice__c();
        insert inv;
        
        Invoice_Line__c invLine = new Invoice_Line__c(
            Invoice__c = inv.Id
        );
        insert invLine; 
        
        invLine.Quantity__c = 5;
        update invLine;

        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;
        
        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId, 
            Product2Id = prod.Id, 
            UnitPrice = 100.00, 
            IsActive = true
        );
        insert pbe;
        
        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = standardPricebookId
        );
        insert ord;
        
        OrderItem item = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            UnitPrice = 100.00
        );
        insert item;
        
        item.Quantity = 5;
        update item;
    }
}