public class ShopifyObjectMappings {

    private static final Map<String, String> CUSTOMER_TO_ACCOUNT_FALLBACK = new Map<String, String>{
        'id'                          => 'Shopify_ID__c',
        'email'                       => 'PersonEmail',
        'first_name'                  => 'FirstName',
        'last_name'                   => 'LastName',
        'phone'                       => 'Phone',
        'tax_exempt'                  => 'Tax_Exempt__c',
        'tags'                        => 'Shopify_Tags__c',
        'total_spent'                 => 'Total_Spent__c',
        'orders_count'                => 'Total_Orders__c',
        'default_address.address1'    => 'BillingStreet',
        'default_address.city'        => 'BillingCity',
        'default_address.province'    => 'BillingState',
        'default_address.zip'         => 'BillingPostalCode',
        'default_address.country'     => 'BillingCountry',
        'sms_marketing_consent.state'         => 'SMS_Consent_State__c',
        'sms_marketing_consent.opt_in_level'  => 'SMS_Opt_In_Level__c',
        'email_marketing_consent.state'       => 'Email_Consent_State__c',
        'email_marketing_consent.opt_in_level' => 'Email_Opt_In_Level__c'
    };

    private static final Map<String, String> ORDER_FALLBACK = new Map<String, String>{
        'id'                   => 'Shopify_ID__c',
        'name'                 => 'OrderReferenceNumber',
        'created_at'           => 'EffectiveDate',
        'total_price'          => 'Total_Amount__c',
        'total_discounts'      => 'Total_Discounts__c',
        'total_tax'            => 'Total_Tax__c',
        'financial_status'     => 'Financial_Status__c',
        'fulfillment_status'   => 'Fulfillment_Status__c',
        'payment_gateway_names' => 'Payment_Gateway__c',
        'contact_email'        => 'Contact_Email__c',
        'cancel_reason'        => 'Cancel_Reason__c'
    };

    private static final Map<String, String> PRODUCT_FALLBACK = new Map<String, String>{
        'id'     => 'Shopify_ID__c',
        'title'  => 'Name',
        'status' => 'IsActive'
    };

    private static final Map<String, String> LINE_ITEM_FALLBACK = new Map<String, String>{
        'id'       => 'Shopify_ID__c',
        'quantity' => 'Quantity',
        'price'    => 'UnitPrice'
    };

    private static Map<String, String> getDynamicMapping(String objectName, String syncDirection) {
        Map<String, String> mapping = new Map<String, String>();
        try {
            List<Field_Mapping__mdt> metadataList = [
                SELECT SF_Field__c, External_Field__c
                FROM Field_Mapping__mdt
                WHERE Integration__c = 'shopify'
                  AND SF_Object__c = :objectName
                  AND Is_Active__c = true
                  AND Sync_Direction__c IN ('Two-Way', :syncDirection)
            ];
            for (Field_Mapping__mdt record : metadataList) {
                if (String.isNotBlank(record.SF_Field__c) && String.isNotBlank(record.External_Field__c)) {
                    mapping.put(record.External_Field__c, record.SF_Field__c);
                }
            }
        } catch (Exception e) {
            System.debug('ShopifyObjectMappings fetch error: ' + e.getMessage());
            ErrorLogUtility.logException(
                'Shopify',
                'ShopifyObjectMappings.getDynamicMapping',
                e,
                null,
                null
            );
        }
        return mapping;
    }

    private static Map<String, String> reverseMapping(Map<String, String> sourceMapping) {
        Map<String, String> reversed = new Map<String, String>();
        for (String shopifyField : sourceMapping.keySet()) {
            String sfField = sourceMapping.get(shopifyField);
            if (String.isNotBlank(shopifyField) && String.isNotBlank(sfField)) {
                reversed.put(sfField, shopifyField);
            }
        }
        return reversed;
    }

    // Shopify Customer → Account (inbound)
    public static Map<String, String> getCustomerToAccountMapping() {
        Map<String, String> dynamic = getDynamicMapping('Account', 'Shopify to SF');
        if (!dynamic.isEmpty()) return dynamic;
        return new Map<String, String>(CUSTOMER_TO_ACCOUNT_FALLBACK);
    }

    // Account → Shopify Customer (outbound)
    public static Map<String, String> getAccountToCustomerMapping() {
        Map<String, String> dynamic = getDynamicMapping('Account', 'SF to Shopify');
        if (!dynamic.isEmpty()) return reverseMapping(dynamic);
        return reverseMapping(new Map<String, String>(CUSTOMER_TO_ACCOUNT_FALLBACK));
    }

    // Shopify Order → Order (inbound)
    public static Map<String, String> getShopifyToOrderMapping() {
        Map<String, String> dynamic = getDynamicMapping('Order', 'Shopify to SF');
        if (!dynamic.isEmpty()) return dynamic;
        return new Map<String, String>(ORDER_FALLBACK);
    }

    // Order → Shopify Order (outbound)
    public static Map<String, String> getOrderToShopifyMapping() {
        Map<String, String> dynamic = getDynamicMapping('Order', 'SF to Shopify');
        if (!dynamic.isEmpty()) return reverseMapping(dynamic);
        return reverseMapping(new Map<String, String>(ORDER_FALLBACK));
    }

    // Shopify Product → Product2 (inbound)
    public static Map<String, String> getShopifyToProductMapping() {
        Map<String, String> dynamic = getDynamicMapping('Product2', 'Shopify to SF');
        if (!dynamic.isEmpty()) return dynamic;
        return new Map<String, String>(PRODUCT_FALLBACK);
    }

    // Product2 → Shopify Product (outbound)
    public static Map<String, String> getProductToShopifyMapping() {
        Map<String, String> dynamic = getDynamicMapping('Product2', 'SF to Shopify');
        if (!dynamic.isEmpty()) return reverseMapping(dynamic);
        return reverseMapping(new Map<String, String>(PRODUCT_FALLBACK));
    }

    // Shopify Line Item → OrderItem (inbound)
    public static Map<String, String> getLineItemMapping() {
        Map<String, String> dynamic = getDynamicMapping('OrderItem', 'Shopify to SF');
        if (!dynamic.isEmpty()) return dynamic;
        return new Map<String, String>(LINE_ITEM_FALLBACK);
    }
}