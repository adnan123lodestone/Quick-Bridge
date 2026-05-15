public class QBTriggerHandler {
    // Prevent recursion
    public static Boolean isAccountProcessing = false;
    public static Boolean isProductProcessing = false;
      public static Boolean isOrderProcessing = false;
    
    // Handler for Account triggers
    public static void handleAccountTrigger(List<Account> newList, Map<Id, Account> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (isAccountProcessing) return;
        isAccountProcessing = true;
        
        try {
            List<Account> accountsToSync = new List<Account>();
            
            for (Account acc : newList) {
                if (shouldSyncAccount(acc, isInsert ? null : oldMap.get(acc.Id))) {
                    accountsToSync.add(acc);
                }
            }
            
            if (!accountsToSync.isEmpty()) {
                for (Account accountRecord : accountsToSync) {
                    IntegrationWorkService.enqueueQuickBooksWork(
                        'AccountUpsert',
                        'Account',
                        accountRecord.Id,
                        'Account:' + String.valueOf(accountRecord.Id),
                        isInsert
                    );
                }
            }
        } catch (Exception e) {
            System.debug('Error in QBTriggerHandler.handleAccountTrigger: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBTriggerHandler.handleAccountTrigger',
                e,
                'Account',
                newList == null || newList.isEmpty() ? null : newList[0].Id
            );
        } finally {
            isAccountProcessing = false;
        }
    }
    
    public static void handleProductTrigger(List<Product2> newList, Map<Id, Product2> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (isProductProcessing) return;
        isProductProcessing = true;
        
        try {
            List<Product2> productsToSync = new List<Product2>();
            
            for (Product2 prod : newList) {
                if (shouldSyncProduct(prod, isInsert ? null : oldMap.get(prod.Id))) {
                    productsToSync.add(prod);
                }
            }
            
            if (!productsToSync.isEmpty()) {
                for (Product2 productRecord : productsToSync) {
                    IntegrationWorkService.enqueueQuickBooksWork(
                        'ProductUpsert',
                        'Product2',
                        productRecord.Id,
                        'Product2:' + String.valueOf(productRecord.Id),
                        isInsert
                    );
                }
            }
        } catch (Exception e) {
            System.debug('Error in QBTriggerHandler.handleProductTrigger: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBTriggerHandler.handleProductTrigger',
                e,
                'Product2',
                newList == null || newList.isEmpty() ? null : newList[0].Id
            );
        } finally {
            isProductProcessing = false;
        }
    }
    
    // Rest of the helper methods remain the same...
    private static Boolean shouldSyncAccount(Account newAcc, Account oldAcc) {
        if (oldAcc == null) return true;
        
        Map<String, String> fieldMap = QBObjectMappings.getAccountToCustomerMapping();
        for (String sfField : fieldMap.keySet()) {
            if (newAcc.get(sfField) != oldAcc.get(sfField)) {
                return true;
            }
        }
        
        return false;
    }
    
    private static Boolean shouldSyncProduct(Product2 newProd, Product2 oldProd) {
        if (oldProd == null) return true;
        
        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();
        for (String sfField : fieldMap.keySet()) {
            if (newProd.get(sfField) != oldProd.get(sfField)) {
                return true;
            }
        }
        
        return false;
    }
    

}
