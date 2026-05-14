public with sharing class InvoiceMappingController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableObjects() {
        List<Map<String, String>> objectList = new List<Map<String, String>>();
        
        for (Schema.SObjectType objTyp : Schema.getGlobalDescribe().Values()) {
            Schema.DescribeSObjectResult describeRes = objTyp.getDescribe();
            if (describeRes.isCustom() && describeRes.isCreateable()) {
                objectList.add(new Map<String, String>{
                    'label' => describeRes.getLabel() + ' (' + describeRes.getName() + ')',
                    'value' => describeRes.getName()
                });
            }
        }
        return objectList;
    }
    
    @AuraEnabled
    public static List<Map<String, String>> getObjectFields(String objectApiName) {
        List<Map<String, String>> fieldList = new List<Map<String, String>>();
        if (String.isBlank(objectApiName)) return fieldList;
        
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectApiName)) return fieldList;
        
        Map<String, Schema.SObjectField> fieldMap = globalDescribe.get(objectApiName).getDescribe().fields.getMap();
        
        Set<String> ignoredFields = new Set<String>{'ownerid', 'recordtypeid', 'currencyisocode', 'createdbyid', 'lastmodifiedbyid', 'systemmodstamp'};
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            String fieldApiName = fieldName.toLowerCase();
            
            if ((fieldDescribe.isCreateable() || !fieldDescribe.isCalculated()) && !ignoredFields.contains(fieldApiName)) {
                fieldList.add(new Map<String, String>{
                    'label' => fieldDescribe.getLabel() + ' (' + fieldName + ')',
                    'value' => fieldName
                });
            }
        }
        return fieldList;
    }
    
    @AuraEnabled
    public static List<Invoice_Field_Mapping__mdt> getExistingMappings(String targetObject) {
        return [SELECT MasterLabel, DeveloperName, Target_Object_API_Name__c, Source_Field_API_Name__c, Target_Field_API_Name__c 
                FROM Invoice_Field_Mapping__mdt 
                WHERE Target_Object_API_Name__c = :targetObject AND Is_Active__c = true];
    }

    @AuraEnabled
    public static String saveMappings(List<Map<String, String>> mappingsToSave) {
        try {
            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            
            for (Map<String, String> mapping : mappingsToSave) {
                Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
                customMetadata.fullName = 'Invoice_Field_Mapping.' + mapping.get('developerName');
                customMetadata.label = mapping.get('label');
                
                Metadata.CustomMetadataValue targetObj = new Metadata.CustomMetadataValue();
                targetObj.field = 'Target_Object_API_Name__c';
                targetObj.value = mapping.get('targetObject');
                customMetadata.values.add(targetObj);
                
                Metadata.CustomMetadataValue sourceField = new Metadata.CustomMetadataValue();
                sourceField.field = 'Source_Field_API_Name__c';
                sourceField.value = mapping.get('sourceField');
                customMetadata.values.add(sourceField);
                
                Metadata.CustomMetadataValue targetField = new Metadata.CustomMetadataValue();
                targetField.field = 'Target_Field_API_Name__c';
                targetField.value = mapping.get('targetField');
                customMetadata.values.add(targetField);
                
                Metadata.CustomMetadataValue isActive = new Metadata.CustomMetadataValue();
                isActive.field = 'Is_Active__c';
                isActive.value = true;
                customMetadata.values.add(isActive);
                
                mdContainer.addMetadata(customMetadata);
            }
            
            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
            return 'Success';
            
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBridge', 'InvoiceMappingController.saveMappings', e, null, null);
            throw new AuraHandledException('Error saving mapping: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String deleteMappingRecord(String developerName) {
        try {
            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            
            customMetadata.fullName = 'Invoice_Field_Mapping.' + developerName;
            customMetadata.label = developerName;
            
            Metadata.CustomMetadataValue isActive = new Metadata.CustomMetadataValue();
            isActive.field = 'Is_Active__c';
            isActive.value = false;
            customMetadata.values.add(isActive);
            
            mdContainer.addMetadata(customMetadata);
            Metadata.Operations.enqueueDeployment(mdContainer, null);
            return 'Success';
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBridge', 'InvoiceMappingController.deleteMappingRecord', e, null, null);
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<Invoice_Field_Mapping__mdt> getAllActiveMappings() {
        return [SELECT MasterLabel, DeveloperName, Target_Object_API_Name__c, Source_Field_API_Name__c, Target_Field_API_Name__c 
                FROM Invoice_Field_Mapping__mdt 
                WHERE Is_Active__c = true LIMIT 100];
    }

    @AuraEnabled
    public static String deactivateAllMappings() {
        try {
            List<Invoice_Field_Mapping__mdt> activeMappings = [SELECT DeveloperName FROM Invoice_Field_Mapping__mdt WHERE Is_Active__c = true];
            
            if (activeMappings.isEmpty()) return 'No active mappings found';

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            
            for (Invoice_Field_Mapping__mdt mdt : activeMappings) {
                Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
                customMetadata.fullName = 'Invoice_Field_Mapping.' + mdt.DeveloperName;
                customMetadata.label = mdt.DeveloperName;
                
                Metadata.CustomMetadataValue isActive = new Metadata.CustomMetadataValue();
                isActive.field = 'Is_Active__c';
                isActive.value = false;
                customMetadata.values.add(isActive);
                
                mdContainer.addMetadata(customMetadata);
            }
            
            Metadata.Operations.enqueueDeployment(mdContainer, null);
            return 'Success';
        } catch (Exception e) {
            ErrorLogUtility.logException('QuickBridge', 'InvoiceMappingController.deactivateAllMappings', e, null, null);
            throw new AuraHandledException('Deactivation failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<Map<String, String>> getRequiredSourceFields() {
        List<Map<String, String>> requiredFields = new List<Map<String, String>>();
        try {
            Set<String> ignoredFields = new Set<String>{'ownerid', 'recordtypeid', 'currencyisocode', 'createdbyid', 'lastmodifiedbyid', 'systemmodstamp'};
            
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get('Invoice__c').getDescribe().fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                String fieldApiName = fieldName.toLowerCase();
                
                if (fieldDescribe.isCreateable() 
                    && !fieldDescribe.isNillable() 
                    && !fieldDescribe.isDefaultedOnCreate()
                    && !ignoredFields.contains(fieldApiName)) {
                    
                    requiredFields.add(new Map<String, String>{
                        'label' => fieldDescribe.getLabel() + ' (' + fieldName + ')',
                        'value' => fieldName
                    });
                }
            }
        } catch(Exception e) {
            System.debug('Error getting required fields: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'InvoiceMappingController.getRequiredSourceFields', e, null, null);
        }
        return requiredFields;
    }

    @AuraEnabled(cacheable=true)
    public static String getCustomInvoiceObjectName() {
        try {
            List<Invoice_Field_Mapping__mdt> activeMappings = [
                SELECT Target_Object_API_Name__c 
                FROM Invoice_Field_Mapping__mdt 
                WHERE Is_Active__c = true 
                LIMIT 1
            ];
            
            if (!activeMappings.isEmpty() && String.isNotBlank(activeMappings[0].Target_Object_API_Name__c)) {
                return activeMappings[0].Target_Object_API_Name__c;
            }
        } catch(Exception e) {
            System.debug('Error getting custom invoice object: ' + e.getMessage());
            ErrorLogUtility.logException('QuickBridge', 'InvoiceMappingController.getCustomInvoiceObjectName', e, null, null);
        }
        return null;
    }
}