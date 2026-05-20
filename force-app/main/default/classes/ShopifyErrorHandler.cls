public class ShopifyErrorHandler {
    public static String handle(Error_Log__c log) {
        Id recordId = log.Source_Record_Id__c;
        String method = log.Class_Method_Name__c;

        // Outbound syncs (Salesforce → Shopify)
        if (method.contains('ShopifyCustomersOutboundBatch.execute')) {
            ShopifyCustomersOutboundBatch batch = new ShopifyCustomersOutboundBatch(new Set<Id>{recordId}, false);
            Database.executeBatch(batch, 1);
            return 'Customer outbound batch enqueued.';
        }
        else if (method.contains('ShopifyOrdersOutboundBatch.execute')) {
            ShopifyOrdersOutboundBatch batch = new ShopifyOrdersOutboundBatch(new Set<Id>{recordId}, false);
            Database.executeBatch(batch, 1);
            return 'Order outbound batch enqueued.';
        }
        else if (method.contains('ShopifyProductsOutboundBatch.execute')) {
            ShopifyProductsOutboundBatch batch = new ShopifyProductsOutboundBatch(new Set<Id>{recordId}, false);
            Database.executeBatch(batch, 1);
            return 'Product outbound batch enqueued.';
        }

        // Inbound syncs (Shopify → Salesforce)
        else if (method.contains('ShopifyCustomersBatch.execute')) {
            ShopifyCustomersBatch.syncCustomerFromShopify(log.Source_Record_Id__c);
            return 'Customer synced from Shopify.';
        }
        else if (method.contains('ShopifyOrdersBatch.execute')) {
            ShopifyOrdersBatch.syncOrderFromShopify(log.Source_Record_Id__c);
            return 'Order synced from Shopify.';
        }
        else if (method.contains('ShopifyProductsBatch.execute')) {
            ShopifyProductsBatch.syncProductFromShopify(log.Source_Record_Id__c);
            return 'Product synced from Shopify.';
        }
        else {
            throw new AuraHandledException('Unsupported Shopify operation: ' + method);
        }
    }
}