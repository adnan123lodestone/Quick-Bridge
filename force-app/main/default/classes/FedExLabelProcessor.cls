global class FedExLabelProcessor {
    
    global class FlowInput {
        @InvocableVariable(required = true)
        public Id caseId;
        
        @InvocableVariable(required = false)
        public String poNumber;
    }
    
    global class FlowOutput {
        @InvocableVariable
        public String message;
        
        @InvocableVariable
        public Boolean isSuccess;
        
        @InvocableVariable
        public String trackingNumber;
        
        @InvocableVariable
        public Id labelId;
    }
    
    @InvocableMethod(label='Generate FedEx Label (All-in-One)'
                     description='Creates label record, generates FedEx shipping label, and attaches PDF.')
    global static List<FlowOutput> processLabel(List<FlowInput> inputs) {
        List<FlowOutput> results = new List<FlowOutput>();
        FlowOutput result = new FlowOutput();
        result.isSuccess = false;

        Id caseId = inputs[0].caseId;
        String poNumber = inputs[0].poNumber;

        try {
            // Step 1: Fetch Case with all required data
            Case caseRecord = [
                SELECT Id, CaseNumber, AccountId, Account.Name, Account.Phone,
                       Shipping_Address__c, 
                       Shipping_Address__r.Street,
                       Shipping_Address__r.City, 
                       Shipping_Address__r.StateCode,
                       Shipping_Address__r.PostalCode,
                       Shipping_Address__r.CountryCode
                FROM Case 
                WHERE Id = :caseId 
                LIMIT 1
            ];

            // Validate Case data
            if (caseRecord.AccountId == null) {
                logFedExError('FedExLabelProcessor.processLabel', 'Case must have an Account.', String.valueOf(caseId));
                result.message = '❌ Case must have an Account.';
                results.add(result);
                return results;
            }

            if (caseRecord.Shipping_Address__c == null) {
                logFedExError('FedExLabelProcessor.processLabel', 'Missing Shipping Address on Case.', String.valueOf(caseId));
                result.message = '❌ Missing Shipping Address on Case.';
                results.add(result);
                return results;
            }

            // Step 2: Check if Label already exists
            List<Label__c> existingLabels = [
                SELECT Id, Name, Master_Tracking_Number__c
                FROM Label__c 
                WHERE Case__c = :caseId 
                LIMIT 1
            ];

            // If label exists with tracking number, return it
            if (!existingLabels.isEmpty() && String.isNotBlank(existingLabels[0].Master_Tracking_Number__c)) {
                result.isSuccess = true;
                result.labelId = existingLabels[0].Id;
                result.trackingNumber = existingLabels[0].Master_Tracking_Number__c;
                result.message = '✅ Label already exists with tracking: ' + result.trackingNumber;
                results.add(result);
                return results;
            }

            // Step 3: Prepare Label data (not inserted yet)
            LabelData labelData = new LabelData();
            labelData.caseId = caseId;
            labelData.caseNumber = caseRecord.CaseNumber;
            labelData.accountId = caseRecord.AccountId;
            labelData.accountName = caseRecord.Account.Name;
            labelData.accountPhone = caseRecord.Account.Phone;
            labelData.serviceType = 'FEDEX_GROUND';
            labelData.packagingType = 'YOUR_PACKAGING';
            labelData.pickupType = 'USE_SCHEDULED_PICKUP';
            labelData.units = 'LB';
            labelData.value = 1;
            labelData.shipDate = Date.today();
            labelData.street = caseRecord.Shipping_Address__r.Street;
            labelData.city = caseRecord.Shipping_Address__r.City;
            labelData.stateCode = caseRecord.Shipping_Address__r.StateCode;
            labelData.postalCode = caseRecord.Shipping_Address__r.PostalCode;
            labelData.countryCode = caseRecord.Shipping_Address__r.CountryCode;

            // Step 4: Make FedEx API callout FIRST
            FedExCalloutResult calloutResult = createShipmentCallout(labelData, poNumber);
            
            if (!calloutResult.isSuccess) {
                result.message = calloutResult.errorMessage;
                results.add(result);
                return results;
            }

            ShipmentData shipmentData = parseShipmentResponse(calloutResult.responseBody);

            if (shipmentData == null || String.isBlank(shipmentData.trackingNumber)) {
                logFedExError('FedExLabelProcessor.processLabel', 'Failed to generate FedEx label. Invalid response. Response: ' + calloutResult.responseBody, String.valueOf(caseId));
                result.message = '❌ Failed to generate FedEx label. Invalid response.';
                results.add(result);
                return results;
            }

            // Step 5: NOW create Label record (only after successful callout)
            Label__c labelRecord = new Label__c(
                Name = labelData.caseNumber,
                Case__c = caseId,
                Account__c = labelData.accountId,
                Master_Tracking_Number__c = shipmentData.trackingNumber,
                Service_Type__c = labelData.serviceType,
                Packaging_Type__c = labelData.packagingType,
                Value__c = labelData.value,
                Pickup_Type__c = labelData.pickupType,
                Units__c = labelData.units,
                Ship_Date_Stamp__c = labelData.shipDate,
                Address__Street__s = labelData.street,
                Address__City__s = labelData.city,
                Address__StateCode__s = labelData.stateCode,
                Address__PostalCode__s = labelData.postalCode,
                Address__CountryCode__s = labelData.countryCode
            );

            insert labelRecord;

            // Step 6: Save label PDF
            saveLabelPDF(labelRecord.Id, caseId, shipmentData.base64Label, labelData.caseNumber);

            result.isSuccess = true;
            result.labelId = labelRecord.Id;
            result.trackingNumber = shipmentData.trackingNumber;
            result.message = '✅ FedEx label generated successfully!\nTracking: ' + shipmentData.trackingNumber;

        } catch (Exception ex) {
            logFedExError('FedExLabelProcessor.processLabel', ex.getMessage() + ' | Line: ' + ex.getLineNumber(), String.valueOf(caseId));
            result.message = '❌ Error: ' + ex.getMessage() + ' | Line: ' + ex.getLineNumber();
        }

        results.add(result);
        return results;
    }

    // --- Helper Methods --- //

    private static FedExCalloutResult createShipmentCallout(LabelData labelData, String poNumber) {
        FedExCalloutResult result = new FedExCalloutResult();
        
        try {
            FedEx_Config__mdt config = [SELECT MasterLabel, Environment__c FROM FedEx_Config__mdt LIMIT 1];
            
            Map<String, Object> body = new Map<String, Object>{
                'labelResponseOptions' => 'LABEL',
                'accountNumber' => new Map<String, Object>{ 'value' => config.MasterLabel }
            };

            // Shipper info
            Map<String, Object> shipper = new Map<String, Object>{
                'contact' => new Map<String, Object>{
                    'personName' => labelData.accountName,
                    'phoneNumber' => labelData.accountPhone
                },
                'address' => new Map<String, Object>{
                    'streetLines' => new List<String>{ labelData.street },
                    'city' => labelData.city,
                    'stateOrProvinceCode' => labelData.stateCode,
                    'postalCode' => labelData.postalCode,
                    'countryCode' => labelData.countryCode
                }
            };

            // Recipient (hardcoded for demo)
            Map<String, Object> recipient = new Map<String, Object>{
                'contact' => new Map<String, Object>{
                    'personName' => 'Brooklyn Taylor',
                    'companyName' => 'Madison Avenue Couture',
                    'phoneNumber' => '+1 (888) 623-2832'
                },
                'address' => new Map<String, Object>{
                    'streetLines' => new List<String>{ '50 West 57th Street, Floor 12A' },
                    'city' => 'New York',
                    'stateOrProvinceCode' => 'NY',
                    'postalCode' => '10019',
                    'countryCode' => 'US'
                }
            };

            // Package info
            Map<String, Object> packageLineItem = new Map<String, Object>{
                'weight' => new Map<String, Object>{
                    'units' => labelData.units,
                    'value' => labelData.value
                },
                'declaredValue' => new Map<String, Object>{
                    'amount' => 500,
                    'currency' => 'USD'
                }
            };

            if (String.isNotBlank(poNumber)) {
                packageLineItem.put('customerReferences', new List<Object>{
                    new Map<String, Object>{
                        'customerReferenceType' => 'P_O_NUMBER',
                        'value' => poNumber
                    }
                });
            }

            Map<String, Object> shipment = new Map<String, Object>{
                'shipper' => shipper,
                'recipients' => new List<Object>{ recipient },
                'shipDatestamp' => String.valueOf(labelData.shipDate),
                'serviceType' => labelData.serviceType,
                'packagingType' => labelData.packagingType,
                'pickupType' => labelData.pickupType,
                'shippingChargesPayment' => new Map<String, Object>{ 'paymentType' => 'SENDER' },
                'labelSpecification' => new Map<String, Object>{
                    'imageType' => 'PDF',
                    'labelStockType' => 'PAPER_85X11_TOP_HALF_LABEL'
                },
                'requestedPackageLineItems' => new List<Object>{ packageLineItem }
            };

            body.put('requestedShipment', shipment);

            String baseUrl = (config.Environment__c == 'Sandbox') 
                ? 'https://apis-sandbox.fedex.com' 
                : 'https://apis.fedex.com';

            String accessToken = FedExAuthService.getAccessToken();

            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + '/ship/v1/shipments');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setBody(JSON.serialize(body));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                result.isSuccess = false;
                result.statusCode = res.getStatusCode();
                result.responseBody = res.getBody();
                result.errorMessage = parseFedExError(res.getBody(), res.getStatusCode());
                logFedExError('FedExLabelProcessor.createShipmentCallout', result.errorMessage, String.valueOf(labelData.caseId));
                return result;
            }

            result.isSuccess = true;
            result.statusCode = res.getStatusCode();
            result.responseBody = res.getBody();
            return result;
            
        } catch (Exception ex) {
            result.isSuccess = false;
            logFedExError('FedExLabelProcessor.createShipmentCallout', ex.getMessage(), labelData == null ? null : String.valueOf(labelData.caseId));
            result.errorMessage = '❌ Callout Exception: ' + ex.getMessage();
            return result;
        }
    }

    private static String parseFedExError(String responseBody, Integer statusCode) {
        String errorMessage = '❌ FedEx API Error (Status ' + statusCode + ')';
        List<String> allErrors = new List<String>();
        
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            
            if (responseMap.containsKey('errors')) {
                List<Object> errors = (List<Object>) responseMap.get('errors');
                if (errors != null && !errors.isEmpty()) {
                    for (Object errObj : errors) {
                        Map<String, Object> err = (Map<String, Object>) errObj;
                        String code = (String) err.get('code');
                        String message = (String) err.get('message');
                        
                        if (String.isNotBlank(code) && String.isNotBlank(message)) {
                            allErrors.add('• [' + code + '] ' + message);
                        }
                    }
                }
            }
            
            if (responseMap.containsKey('output')) {
                Map<String, Object> output = (Map<String, Object>) responseMap.get('output');
                if (output.containsKey('alerts')) {
                    List<Object> alerts = (List<Object>) output.get('alerts');
                    if (alerts != null && !alerts.isEmpty()) {
                        for (Object alertObj : alerts) {
                            Map<String, Object> alert = (Map<String, Object>) alertObj;
                            String code = (String) alert.get('code');
                            String message = (String) alert.get('message');
                            
                            if (String.isNotBlank(code) && String.isNotBlank(message)) {
                                allErrors.add('• [' + code + '] ' + message);
                            }
                        }
                    }
                }
            }
            
            if (!allErrors.isEmpty()) {
                errorMessage = '❌ FedEx API Error:\n\n' + String.join(allErrors, '\n');
            } else {
                errorMessage = '❌ FedEx API Error (Status ' + statusCode + '):\n\n' + 
                              responseBody.abbreviate(500);
            }
            
        } catch (Exception ex) {
            errorMessage = '❌ FedEx API Error (Status ' + statusCode + '):\n\n' + 
                          'Unable to parse error response. Raw response: ' + 
                          responseBody.abbreviate(500);
        }
        
        return errorMessage;
    }

    private static ShipmentData parseShipmentResponse(String responseBody) {
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            if (!responseMap.containsKey('output')) return null;
            Map<String, Object> output = (Map<String, Object>) responseMap.get('output');

            List<Object> transactionShipments = (List<Object>) output.get('transactionShipments');
            if (transactionShipments == null || transactionShipments.isEmpty()) return null;

            Map<String, Object> shipment = (Map<String, Object>) transactionShipments[0];
            String trackingNum = (String) shipment.get('masterTrackingNumber');

            List<Object> pieceResponses = (List<Object>) shipment.get('pieceResponses');
            if (pieceResponses == null || pieceResponses.isEmpty()) return null;

            Map<String, Object> pieceResp = (Map<String, Object>) pieceResponses[0];
            List<Object> packageDocs = (List<Object>) pieceResp.get('packageDocuments');
            if (packageDocs == null || packageDocs.isEmpty()) return null;

            Map<String, Object> packageDoc = (Map<String, Object>) packageDocs[0];
            String base64Label = (String) packageDoc.get('encodedLabel');

            if (String.isNotBlank(trackingNum) && String.isNotBlank(base64Label)) {
                ShipmentData data = new ShipmentData();
                data.trackingNumber = trackingNum;
                data.base64Label = base64Label;
                return data;
            }
        } catch (Exception ex) {
            logFedExError('FedExLabelProcessor.parseShipmentResponse', 'Error parsing FedEx response: ' + ex.getMessage(), null);
        }
        return null;
    }

    private static void saveLabelPDF(Id labelId, Id caseId, String base64Label, String labelName) {
        ContentVersion cv = new ContentVersion(
            Title = 'FedEx Label - ' + labelName,
            PathOnClient = 'FedExLabel_' + labelName + '.pdf',
            VersionData = EncodingUtil.base64Decode(base64Label),
            Origin = 'H'
        );
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        
        // Attach to both Case AND Label record
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        
        links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = caseId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        ));
        
        links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = labelId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        ));
        
        insert links;
    }

    // --- Inner Classes --- //
    
    private class FedExCalloutResult {
        public Boolean isSuccess;
        public Integer statusCode;
        public String responseBody;
        public String errorMessage;
        
        public FedExCalloutResult() {
            this.isSuccess = false;
        }
    }

    private class ShipmentData {
        public String trackingNumber;
        public String base64Label;
    }
    
    private class LabelData {
        public Id caseId;
        public String caseNumber;
        public Id accountId;
        public String accountName;
        public String accountPhone;
        public String serviceType;
        public String packagingType;
        public String pickupType;
        public String units;
        public Decimal value;
        public Date shipDate;
        public String street;
        public String city;
        public String stateCode;
        public String postalCode;
        public String countryCode;
    }

    private static void logFedExError(String classMethodName, String message, String relatedId) {
        ErrorLogUtility.logPaymentError('FedEx', classMethodName, message, relatedId);
    }
}
