public without sharing class QuickbridgeLegacyConfigCompatibility {
    public class ServerOrgConfig {
        public String companyName;
        public String username;
        public String password;
    }

    public static ServerOrgConfig loadServerOrgConfig(Boolean allowCompanyOnly) {
        List<Quickbridge_Config__mdt> configs;
        if (allowCompanyOnly == true) {
            configs = [
                SELECT Company_Name__c, Username__c, Password__c
                FROM Quickbridge_Config__mdt
                WHERE Company_Name__c != NULL
                LIMIT 1
            ];
        } else {
            configs = [
                SELECT Company_Name__c, Username__c, Password__c
                FROM Quickbridge_Config__mdt
                WHERE Username__c != NULL
                    AND Password__c != NULL
                    AND Company_Name__c != NULL
                LIMIT 1
            ];
        }
        if (configs.isEmpty()) {
            if (allowCompanyOnly == true) {
                return null;
            }
            throw new AuraHandledException('No valid credentials found in QuickBridge Metadata.');
        }
        Quickbridge_Config__mdt row = configs[0];
        ServerOrgConfig config = new ServerOrgConfig();
        config.companyName = row.Company_Name__c;
        config.username = row.Username__c;
        config.password = row.Password__c;
        return config;
    }
}
