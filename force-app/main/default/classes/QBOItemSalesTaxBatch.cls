public class QBOItemSalesTaxBatch implements Database.Batchable<Object>, Database.AllowsCallouts, Database.Stateful {
    
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private Integer currentPosition = 1;
    private Boolean hasMoreRecords = true;
    
    public Iterable<Object> start(Database.BatchableContext bc) {
        return new List<Object>{ currentPosition };
    }
    
    public void execute(Database.BatchableContext bc, List<Object> scope) {
        List<Error_Log__c> bulkErrorLogsToInsert = new List<Error_Log__c>();
        List<QuickBridgeTLG__Item_Sales_Tax__c> recordsToUpsert = new List<QuickBridgeTLG__Item_Sales_Tax__c>();
        
        try {
            String query = 'SELECT * FROM TaxCode WHERE Active = true STARTPOSITION ' + currentPosition + ' MAXRESULTS 100';
            String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
            String resource = '/query?query=' + encodedQuery;
            
            HttpResponse res = QuickBooksAuthHandler.makeApiCall('GET', resource, null);
            if (res == null || res.getStatusCode() != 200) {
                throw new CalloutException('Failed to fetch tax codes: ' + (res == null ? 'Null' : res.getBody()));
            }
            
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> queryResponse = (Map<String, Object>) response.get('QueryResponse');
            
            if (queryResponse == null) {
                hasMoreRecords = false;
                return;
            }
            
            List<Object> taxCodes = (List<Object>) queryResponse.get('TaxCode');
            if (taxCodes == null || taxCodes.isEmpty()) {
                hasMoreRecords = false;
                return;
            }
            
            Map<String, String> inboundMapping = QBObjectMappings.getTaxCodeInboundMapping();
            
            for (Object taxObj : taxCodes) {
                try {
                    Map<String, Object> taxCode = (Map<String, Object>) taxObj;
                    String taxCodeId = (String) taxCode.get('Id');
                    if (String.isBlank(taxCodeId)) continue;
                    
                    QuickBridgeTLG__Item_Sales_Tax__c sfTax = new QuickBridgeTLG__Item_Sales_Tax__c();
                    sfTax.QuickBridgeTLG__External_Id__c = taxCodeId;
                    
                    for (String qboField : inboundMapping.keySet()) {
                        String sfField = inboundMapping.get(qboField);
                        Object value = getNestedValue(taxCode, qboField);
                        if (value != null) {
                            sfTax.put(sfField, value);
                        }
                    }
                    
                    // Bulk Validation Fallbacks
                    if (String.isBlank((String) sfTax.get('Name'))) {
                        sfTax.Name = (String) taxCode.get('Name');
                    }
                    if (sfTax.get('QuickBridgeTLG__Is_Active__c') == null) {
                        sfTax.QuickBridgeTLG__Is_Active__c = (Boolean) taxCode.get('Active');
                    }
                    if (sfTax.get('QuickBridgeTLG__Item_Description__c') == null) {
                        sfTax.QuickBridgeTLG__Item_Description__c = (String) taxCode.get('Description');
                    }
                    if (sfTax.get('QuickBridgeTLG__Tax_Rate_Per__c') == null) {
                        Object rate = getNestedValue(taxCode, 'SalesTaxRateList.TaxRateDetail[0].TaxRateRef.value');
                        if (rate != null) {
                            sfTax.QuickBridgeTLG__Tax_Rate_Per__c = Decimal.valueOf(String.valueOf(rate));
                        }
                    }
                    
                    sfTax.QuickBridgeTLG__Is_Synced__c = true;
                    recordsToUpsert.add(sfTax);
                    successCount++;
                    
                } catch (Exception innerEx) {
                    errorCount++;
                    ErrorLogUtility.logException(
                        'QuickBooks',
                    'QBOItemSalesTaxBatch.execute.processRow',
                    innerEx,
                    'Item_Sales_Tax__c',
                    null
                        );
                }
            }
            
            Integer maxResults = (Integer) queryResponse.get('maxResults');
            Integer totalCount = (Integer) queryResponse.get('totalCount');
            
            if (currentPosition + maxResults <= totalCount) {
                currentPosition += maxResults;
                hasMoreRecords = true;
            } else {
                hasMoreRecords = false;
            }
            
        } catch (Exception fatalEx) {
            errorCount++;
            System.debug('Fatal batch chunk failure exception triggered: ' + fatalEx.getMessage());
            ErrorLogUtility.logException('QuickBooks', 'QBOItemSalesTaxBatch.execute', fatalEx, null, null);
            hasMoreRecords = false;
        } finally {
            if (!recordsToUpsert.isEmpty()) {
                Database.UpsertResult[] results = Database.upsert(recordsToUpsert,
                QuickBridgeTLG__Item_Sales_Tax__c.QuickBridgeTLG__External_Id__c, false);
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorCount++;
                        successCount--;
                        String errorMsg = results[i].getErrors()[0].getMessage();
                        System.debug('Upsert failed for record ID: ' + recordsToUpsert[i].QuickBridgeTLG__External_Id__c + ' Error: ' + errorMsg);
                        // Log as an error record
                        ErrorLogUtility.logCalloutFailure(
                            'QuickBooks',
                        'QBOItemSalesTaxBatch.execute.upsert',
                        'Upsert failed for External_Id__c ' + recordsToUpsert[i].QuickBridgeTLG__External_Id__c + ': ' + errorMsg,
                        null,
                        'Item_Sales_Tax__c',
                        null
                            );
                    }
                }
            }
            recordsToUpsert.clear();
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('QBOItemSalesTaxBatch Bulk Execution Pipeline Completed. Success Rows: ' + successCount + ', Error Rows: ' + errorCount);
        
        if (hasMoreRecords) {
            QBOItemSalesTaxBatch nextJob = new QBOItemSalesTaxBatch();
            nextJob.currentPosition = this.currentPosition;
            Database.executeBatch(nextJob, 1);
        }
    }
    
    private Object getNestedValue(Map<String, Object> obj, String fieldPath) {
        if (String.isBlank(fieldPath)) return null;
        String[] parts = fieldPath.split('\\.');
        Object current = obj;
        for (String part : parts) {
            if (current == null) return null;
            if (part.contains('[') && part.contains(']')) {
                String arrayName = part.substringBefore('[');
                Integer index = Integer.valueOf(part.substringBetween('[', ']'));
                Map<String, Object> mapCurrent = (Map<String, Object>) current;
                List<Object> arr = (List<Object>) mapCurrent.get(arrayName);
                if (arr == null || arr.size() <= index) return null;
                current = arr[index];
            } else {
                Map<String, Object> mapCurrent = (Map<String, Object>) current;
                current = mapCurrent.get(part);
            }
        }
        return current;
    }
}