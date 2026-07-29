public class QBTriggerHandler {
    // Prevent recursion
    public static Boolean isAccountProcessing = false;
    public static Boolean isProductProcessing = false;
    public static Boolean isOrderProcessing = false;
    public static Boolean isQuoteProcessing = false;
    
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
    
    // Handler for Product triggers
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

    // Handler for Quote triggers
    public static void handleQuoteTrigger(List<Quote> newList, Map<Id, Quote> oldMap, Boolean isInsert, Boolean isUpdate) {
        if (isQuoteProcessing) return;
        isQuoteProcessing = true;
        
        try {
            List<Quote> quotesToSync = new List<Quote>();
            
            for (Quote q : newList) {
                if (shouldSyncQuote(q, (isInsert || oldMap == null) ? null : oldMap.get(q.Id))) {
                    quotesToSync.add(q);
                }
            }
            
            if (!quotesToSync.isEmpty()) {
                for (Quote quoteRecord : quotesToSync) {
                    IntegrationWorkService.enqueueQuickBooksWork(
                        'QuoteUpsert',
                        'Quote',
                        quoteRecord.Id,
                        'Quote:' + String.valueOf(quoteRecord.Id),
                        isInsert
                    );
                }
            }
        } catch (Exception e) {
            System.debug('Error in QBTriggerHandler.handleQuoteTrigger: ' + e.getMessage());
            ErrorLogUtility.logException(
                'QuickBooks',
                'QBTriggerHandler.handleQuoteTrigger',
                e,
                'Quote',
                newList == null || newList.isEmpty() ? null : newList[0].Id
            );
        } finally {
            isQuoteProcessing = false;
        }
    }

    private static Boolean shouldSyncAccount(Account newAcc, Account oldAcc) {
        if (oldAcc == null) return true;
        
        Map<String, String> fieldMap = QBObjectMappings.getAccountToCustomerMapping();
        for (String sfField : fieldMap.keySet()) {
            try {
                if (newAcc.get(sfField) != oldAcc.get(sfField)) return true;
            } catch (Exception e) {}
        }
        
        return false;
    }
    
    private static Boolean shouldSyncProduct(Product2 newProd, Product2 oldProd) {
        if (oldProd == null) return true;
        
        Map<String, String> fieldMap = QBObjectMappings.getProductToItemMapping();
        for (String sfField : fieldMap.keySet()) {
            try {
                if (newProd.get(sfField) != oldProd.get(sfField)) return true;
            } catch (Exception e) {}
        }
        
        return false;
    }

    private static Boolean shouldSyncQuote(Quote newQuote, Quote oldQuote) {
        if (oldQuote == null) return true;
        
        Map<String, String> fieldMap = QBObjectMappings.getQuoteMapping();
        for (String sfField : fieldMap.keySet()) {
            try {
                if (newQuote.get(sfField) != oldQuote.get(sfField)) return true;
            } catch (Exception e) {}
        }
        
        return false;
    }
}