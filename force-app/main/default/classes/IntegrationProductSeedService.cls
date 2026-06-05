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

    @AuraEnabled
    public static String reseedSystemManagedProducts() {
        QuickBridgeAdminGuard.requireManage();
        seedDefaultProducts();
        return 'Success: QuickBridge system-managed integration products reseeded.';
    }

    @TestVisible
    static List<Integration_Product__c> defaultProducts() {
        return metadataDefaultProducts();
    }

    private static List<Integration_Product__c> metadataDefaultProducts() {
        List<Integration_Product__c> products = new List<Integration_Product__c>();
        try {
            for (Integration_Product_Default__mdt row : [
                SELECT Product_Key__c, Connector_Key__c, Product_Label__c, Aliases__c, Category__c,
                    Display_Order__c, Logo_URL__c, Config_Record_Name__c, Active_Field__c,
                    Expiry_Field__c, Editable_Fields__c, Enabled__c, Catalog_Active__c,
                    Status__c, Has_Config__c, Has_Reporting__c, Has_Mapping__c,
                    Has_Scheduler__c, Has_Checkout__c, Has_Payment__c, Has_Carrier__c
                FROM Integration_Product_Default__mdt
                WHERE Enabled__c = true
                ORDER BY Display_Order__c ASC, Product_Label__c ASC
            ]) {
                products.add(product(
                    row.Product_Label__c,
                    row.Product_Key__c,
                    row.Connector_Key__c,
                    row.Product_Label__c,
                    row.Aliases__c,
                    row.Category__c,
                    row.Display_Order__c == null ? 999 : row.Display_Order__c.intValue(),
                    row.Logo_URL__c,
                    row.Config_Record_Name__c,
                    row.Active_Field__c,
                    row.Expiry_Field__c,
                    row.Editable_Fields__c,
                    row.Has_Config__c == true,
                    row.Has_Mapping__c == true,
                    row.Has_Scheduler__c == true,
                    row.Has_Checkout__c == true,
                    row.Has_Payment__c == true,
                    row.Has_Carrier__c == true
                ));
            }
        } catch (Exception ignored) {
        }
        return products;
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
            Has_Carrier__c = hasCarrier,
            System_Managed__c = true
        );
    }
}