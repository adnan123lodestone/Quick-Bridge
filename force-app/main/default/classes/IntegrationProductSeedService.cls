public with sharing class IntegrationProductSeedService {
    @TestVisible
    private static final String UPS_CDN_LOGO_URL = 'https://cdn.worldvectorlogo.com/logos/ups-1.svg';

    public static void seedDefaultProducts() {
        List<Integration_Product__c> products = defaultProducts();
        if (products.isEmpty()) {
            return;
        }
        upsert products Integration_Product__c.Product_Key__c;
        repairKnownLogoOverrides();
        IntegrationConnectorRegistry.clearCache();
    }

    @TestVisible
    static List<Integration_Product__c> defaultProducts() {
        return new List<Integration_Product__c>{
            product('QuickBooks', 'quickbooks', 'qbo', 'QuickBooks', 'qbo,quickbooks,quickbooksonline,quickbooks online', 'Accounting', 10, null, 'QuickBooks', 'QuickBooks_Is_Active__c', 'QuickBooks_End_Date__c', 'Company_Name__c,QuickBooks_Realm_ID__c,QuickBooks_Is_Active__c,QuickBooks_Start_Date__c,QuickBooks_End_Date__c', true, true, true, false, false, false),
            product('Shopify', 'shopify', 'shopify', 'Shopify', 'shopify', 'Commerce', 20, 'https://cdn.worldvectorlogo.com/logos/shopify.svg', 'Shopify', 'Shopify_Is_Active__c', 'Shopify_End_Date__c', 'Company_Name__c,Shopify_Store_URL__c,Shopify_Access_Token__c,Shopify_API_Key__c,Shopify_API_Secret__c,Shopify_Is_Active__c,Shopify_Start_Date__c,Shopify_End_Date__c', true, true, true, false, false, false),
            product('Stripe', 'stripe', 'stripe', 'Stripe', 'stripe', 'Payment', 30, 'https://cdn.worldvectorlogo.com/logos/stripe-4.svg', 'Stripe', 'Stripe_Active__c', 'Stripe_End_Date__c', 'Company_Name__c,Stripe_Publishable_Key__c,Stripe_Webhook_Signing_Secret__c,Stripe_Active__c,Stripe_Use_Sandbox__c,Stripe_Start_Date__c,Stripe_End_Date__c', true, true, false, true, true, false),
            product('Authorize.Net', 'authorizenet', 'authorizenet', 'Authorize.Net', 'authorizenet,authorize.net,authorize net,authnet', 'Payment', 40, null, 'AuthorizeNet', 'AuthorizeNet_Active__c', 'AuthorizeNet_End_Date__c', 'Company_Name__c,AuthorizeNet_API_Login_ID__c,AuthorizeNet_Public_Client_Key__c,AuthorizeNet_Webhook_Signing_Key__c,AuthorizeNet_Active__c,AuthorizeNet_Use_Sandbox__c,AuthorizeNet_Start_Date__c,AuthorizeNet_End_Date__c', true, false, false, true, true, false),
            product('PayPal', 'paypal', 'paypal', 'PayPal', 'paypal,pay pal', 'Payment', 50, 'https://cdn.worldvectorlogo.com/logos/paypal-3.svg', 'PayPal', 'PayPal_Active__c', 'PayPal_EndDate__c', 'Company_Name__c,PayPal_ClientId__c,PayPal_Active__c,PayPal_UseSandbox__c,PayPal_StartDate__c,PayPal_EndDate__c', true, false, false, true, true, false),
            product('FedEx', 'fedex', 'fedex', 'FedEx', 'fedex', 'Carrier', 60, null, 'FedEx', 'FedEx_Active__c', 'FedEx_End_Date__c', 'FedEx_Client_Id__c,FedEx_Client_Secret__c,FedEx_Account_Number__c,FedEx_Environment__c,FedEx_Default_Service_Type__c,FedEx_Default_Packaging_Type__c,FedEx_Default_Pickup_Type__c,FedEx_Active__c,FedEx_Start_Date__c,FedEx_End_Date__c', true, true, false, false, false, true),
            product('UPS', 'ups', 'ups', 'UPS', 'ups', 'Carrier', 70, null, 'UPS', 'UPS_Active__c', 'UPS_End_Date__c', 'UPS_Client_Id__c,UPS_Client_Secret__c,UPS_Account_Number__c,UPS_Environment__c,UPS_Default_Service_Code__c,UPS_Active__c,UPS_Start_Date__c,UPS_End_Date__c', true, true, false, false, false, true)
        };
    }

    @TestVisible
    static void repairKnownLogoOverrides() {
        List<Integration_Product__c> productsToRepair = [
            SELECT Id, Logo_URL__c
            FROM Integration_Product__c
            WHERE (Product_Key__c IN ('ups', 'UPS') OR Connector_Key__c IN ('ups', 'UPS'))
            AND Logo_URL__c = :UPS_CDN_LOGO_URL
        ];
        if (productsToRepair.isEmpty()) {
            return;
        }
        for (Integration_Product__c productRow : productsToRepair) {
            productRow.Logo_URL__c = null;
        }
        update productsToRepair;
    }

    private static Integration_Product__c product(
        String nameValue,
        String productKey,
        String connectorKey,
        String label,
        String aliases,
        String category,
        Integer displayOrder,
        String logoUrl,
        String configRecordName,
        String activeField,
        String expiryField,
        String editableFields,
        Boolean hasConfig,
        Boolean hasMapping,
        Boolean hasScheduler,
        Boolean hasCheckout,
        Boolean hasPayment,
        Boolean hasCarrier
    ) {
        return new Integration_Product__c(
            Name = nameValue,
            Product_Key__c = productKey,
            Connector_Key__c = connectorKey,
            Product_Label__c = label,
            Aliases__c = aliases,
            Category__c = category,
            Display_Order__c = displayOrder,
            Logo_URL__c = logoUrl,
            Config_Record_Name__c = configRecordName,
            Active_Field__c = activeField,
            Expiry_Field__c = expiryField,
            Editable_Fields__c = editableFields,
            Enabled__c = true,
            Catalog_Active__c = true,
            Status__c = 'Available',
            Has_Config__c = hasConfig,
            Has_Reporting__c = true,
            Has_Mapping__c = hasMapping,
            Has_Scheduler__c = hasScheduler,
            Has_Checkout__c = hasCheckout,
            Has_Payment__c = hasPayment,
            Has_Carrier__c = hasCarrier
        );
    }
}