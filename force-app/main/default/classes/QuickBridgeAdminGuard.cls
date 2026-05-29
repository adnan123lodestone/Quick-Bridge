public with sharing class QuickBridgeAdminGuard {
    @TestVisible private static Boolean bypassForTests;

    public static void requireManage() {
        requirePermission('Manage_QuickBridge', 'manage QuickBridge settings');
    }

    public static void requireView() {
        if (hasPermission('View_QuickBridge') || hasPermission('Manage_QuickBridge')) {
            return;
        }
        throw new AuraHandledException('You do not have permission to view QuickBridge settings.');
    }

    public static void requireRunSync() {
        if (hasPermission('Run_QuickBridge_Sync') || hasPermission('Manage_QuickBridge')) {
            return;
        }
        throw new AuraHandledException('You do not have permission to run QuickBridge sync operations.');
    }

    public static Boolean hasManage() {
        return hasPermission('Manage_QuickBridge');
    }

    public static Boolean hasView() {
        return hasPermission('View_QuickBridge') || hasManage();
    }

    public static Boolean hasRunSync() {
        return hasPermission('Run_QuickBridge_Sync') || hasManage();
    }

    public static void audit(String action, String connectorKey, String status, String details, Id relatedRecordId) {
        try {
            insert new QuickBridge_Admin_Audit__c(
                Action__c = action,
                Connector_Key__c = connectorKey,
                Status__c = status,
                Details__c = details,
                Actor_User__c = UserInfo.getUserId(),
                Related_Record_Id__c = relatedRecordId == null ? null : String.valueOf(relatedRecordId)
            );
        } catch (Exception ignored) {
        }
    }

    private static void requirePermission(String permissionName, String actionLabel) {
        if (!hasPermission(permissionName)) {
            throw new AuraHandledException('You do not have permission to ' + actionLabel + '.');
        }
    }

    private static Boolean hasPermission(String permissionName) {
        if (Test.isRunningTest() && bypassForTests != false) {
            return true;
        }
        return FeatureManagement.checkPermission(permissionName);
    }
}