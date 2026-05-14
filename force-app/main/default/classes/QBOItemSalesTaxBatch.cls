public class QBOItemSalesTaxBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    public Integer successCount = 0;
    public Integer errorCount = 0;
    public Datetime lastSyncDate;
    
    public QBOItemSalesTaxBatch(Datetime inputDate){
        if(inputDate != null){
            lastSyncDate = inputDate;
        } else {
            lastSyncDate = System.now().addDays(-1);
        }
    }
    
    public QBOItemSalesTaxBatch(){
        lastSyncDate = System.now().addDays(-1);
    }
    
    // START
    public Database.QueryLocator start(Database.BatchableContext bc){
        String query = 'SELECT Id, Name, QuickBridgeTLG__External_Id__c, ' +
            'QuickBridgeTLG__Is_Active__c, QuickBridgeTLG__Is_Synced__c, ' +
            'QuickBridgeTLG__Item_Description__c, ' +
            'QuickBridgeTLG__Tax_Rate_Per__c, LastModifiedDate ' +
            'FROM QuickBridgeTLG__Item_Sales_Tax__c ' +
            'WHERE LastModifiedDate >= :lastSyncDate';
        return Database.getQueryLocator(query);
    }
    
    // EXECUTE
    public void execute(Database.BatchableContext bc, List<QuickBridgeTLG__Item_Sales_Tax__c> scope){
        List<QuickBridgeTLG__Item_Sales_Tax__c> recordsToUpdate = new List<QuickBridgeTLG__Item_Sales_Tax__c>();
        
        for(QuickBridgeTLG__Item_Sales_Tax__c tax : scope){
            try{
                if(String.isBlank(tax.QuickBridgeTLG__External_Id__c)){
                    createTaxRate(tax);
                } else {
                    updateTaxRate(tax);
                }
                
                tax.QuickBridgeTLG__Is_Synced__c = true;
                recordsToUpdate.add(tax);
                successCount++;
                
            } catch(Exception e){
                errorCount++;
                System.debug('Error processing Tax Record ' + tax.Id + ': ' + e.getMessage());
                ErrorLogUtility.logException(
                    'QuickBooks',
                    'QBOItemSalesTaxBatch.execute.processTax',
                    e,
                    'Item_Sales_Tax__c',
                    tax == null ? null : tax.Id
                );
            }
        }
        
        // Safe Update - Partial success allowed
        if(!recordsToUpdate.isEmpty()){
            Database.SaveResult[] updateResults = Database.update(recordsToUpdate, false);
            ErrorLogUtility.logDmlResults(
                'QuickBooks',
                'QBOItemSalesTaxBatch.execute.updateTaxes',
                'update',
                recordsToUpdate,
                updateResults,
                null,
                null
            );
        }
    }
    
    // FINISH
    public void finish(Database.BatchableContext bc){
        System.debug('QBOItemSalesTaxBatch Completed.');
        System.debug('Total Success: ' + successCount);
        System.debug('Total Errors: ' + errorCount);
    }
    
    // ===============================
    // CREATE TAX RATE IN QBO (AST SUPPORTED - DYNAMIC MAPPING)
    // ===============================
    private void createTaxRate(QuickBridgeTLG__Item_Sales_Tax__c tax){
        
        String agencyId = '1'; 
        try {
            QuickBridgeTLG__Quickbridge_Config__mdt config = [
                SELECT QuickBridgeTLG__Quickbooks_Default_Tax_Agency_Id__c 
                FROM QuickBridgeTLG__Quickbridge_Config__mdt 
                WHERE DeveloperName = 'QuickBooks' LIMIT 1
            ];
            if(String.isNotBlank(config.QuickBridgeTLG__Quickbooks_Default_Tax_Agency_Id__c)) {
                agencyId = config.QuickBridgeTLG__Quickbooks_Default_Tax_Agency_Id__c;
            }
        } catch (Exception ex) {}

        // 1. Dynamic Mapping 
        Map<String, String> fieldMapping = QBObjectMappings.getTaxCodeMapping();
        
        Map<String, Object> taxRateDetails = new Map<String, Object>();
        taxRateDetails.put('TaxAgencyId', agencyId);
        taxRateDetails.put('TaxApplicableOn', 'Sales');

        Map<String, Object> body = new Map<String, Object>();

        for(String sfField : fieldMapping.keySet()) {
            String qbField = fieldMapping.get(sfField);
            Object value = tax.get(sfField);
            
            if(value != null) {
                if(qbField == 'RateValue' || qbField == 'TaxRateName') {
                    taxRateDetails.put(qbField, value);
                }
                else {
                    if(qbField == 'TaxCode' || qbField == 'Active' || qbField == 'Description') {
                        body.put(qbField, value);
                    }
                }
            }
        }
        
        if(!body.containsKey('TaxCode')) {
            body.put('TaxCode', tax.Name);
        }
        if(!taxRateDetails.containsKey('TaxRateName')) {
            taxRateDetails.put('TaxRateName', tax.Name);
        }

        // Finalize AST Body Structure
        body.put('TaxRateDetails', new List<Object>{ taxRateDetails });

        String requestBody = JSON.serialize(body);
        
        // API Call for Creation
        HttpResponse res = QuickBooksAuthHandler.makeApiCall('POST', '/taxservice/taxcode', requestBody);

        if(res.getStatusCode() == 200){
            Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            
            if(parsed.containsKey('TaxCodeId')){
                tax.QuickBridgeTLG__External_Id__c = String.valueOf(parsed.get('TaxCodeId'));
            } else if(parsed.containsKey('TaxCode')) {
                 Map<String,Object> tc = (Map<String,Object>) parsed.get('TaxCode');
                 tax.QuickBridgeTLG__External_Id__c = (String) tc.get('Id');
            }
        } else {
            throw new CalloutException('Create Failed: ' + res.getBody());
        }
    }
    
    // ===============================
    // UPDATE TAX RATE IN QBO
    // ===============================
    private void updateTaxRate(QuickBridgeTLG__Item_Sales_Tax__c tax){
        HttpResponse queryRes = QuickBooksAuthHandler.makeApiCall('GET', '/taxcode/' + tax.QuickBridgeTLG__External_Id__c, null);
        
        if (queryRes.getStatusCode() != 200) {
            throw new CalloutException('Error querying existing Tax Code: ' + queryRes.getBody());
        }
        
        Map<String, Object> existingData = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
        Map<String, Object> existingTaxCode = (Map<String, Object>) existingData.get('TaxCode');
        String syncToken = (String) existingTaxCode.get('SyncToken');
        
        Map<String, Object> body = new Map<String, Object>{
            'Id' => tax.QuickBridgeTLG__External_Id__c,
            'SyncToken' => syncToken,
            'Name' => tax.Name,
            'Active' => tax.QuickBridgeTLG__Is_Active__c
        };
        
        String requestBody = JSON.serialize(body);
        HttpResponse updateRes = QuickBooksAuthHandler.makeApiCall('POST', '/taxcode', requestBody);
        
        if(updateRes.getStatusCode() != 200){
            throw new CalloutException('Update Failed: ' + updateRes.getBody());
        }
    }
}