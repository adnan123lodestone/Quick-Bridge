global class FedExBulkLabelProcessor {
	
	global class CaseInput {
		@InvocableVariable(required = true)
		public Id caseId;
		
		@InvocableVariable(required = false)
		public String poNumber;
	}

	@InvocableMethod(
		label = 'Generate FedEx Labels in Bulk'
		description = 'Generate FedEx shipping labels for Cases and their child Cases'
	)
	global static List<BulkLabelResult> generateLabel(List<CaseInput> requestList) {
		List<BulkLabelResult> results = new List<BulkLabelResult>();
		List<Id> caseIds = new List<Id>();
		String flowPONumber = null;

		for (CaseInput req: requestList) {
			caseIds.add(req.caseId);
			flowPONumber = req.poNumber;
		}

		if (caseIds.isEmpty()) {
			logFedExError('FedExBulkLabelProcessor.generateLabel', 'No Case Ids were provided.', null);
			BulkLabelResult errorResult = new BulkLabelResult();
			errorResult.message = '⚠️ No Case Ids were provided.';
			errorResult.isSuccess = false;
			results.add(errorResult);
			return results;
		}

		// Step 1 & 2: Collect provided Cases + their child Cases
		List<Case> allCases = [
			SELECT Id, Brand_Name__c, CaseNumber, Shipping_and_Accompaniments__c, Risk_of_Loss__c
			FROM Case WHERE Id IN: caseIds OR ParentId IN: caseIds
		];
        
		if (allCases.isEmpty()) {
			logFedExError('FedExBulkLabelProcessor.generateLabel', 'No cases found for given Ids.', String.valueOf(caseIds));
			BulkLabelResult errorResult = new BulkLabelResult();
			errorResult.message = 'ℹ️ No cases found for given Ids.';
			errorResult.isSuccess = false;
			results.add(errorResult);
			return results;
		}

		List<String> invalidCaseNumbers = new List<String>();
		List<String> invalidShippingCases = new List<String>();
		List<String> invalidRiskCases = new List<String>();

		for (Case c: allCases) {
			if (caseIds.contains(c.Id)) { // Only check parent cases
				if (String.isBlank(c.Shipping_and_Accompaniments__c)) {
					invalidShippingCases.add(c.CaseNumber);
				}

				if (String.isBlank(c.Risk_of_Loss__c)) {
					invalidRiskCases.add(c.CaseNumber);
				}
			}
		}

		if (!invalidShippingCases.isEmpty()) {
			logFedExError('FedExBulkLabelProcessor.generateLabel', 'Shipping and Accompaniments is missing for Cases: ' + String.join(invalidShippingCases, ', '), String.valueOf(caseIds));
			BulkLabelResult errorResult = new BulkLabelResult();
			errorResult.message = '❌ Shipping and Accompaniments is missing for Cases: ' + String.join(invalidShippingCases, ', ');
			errorResult.isSuccess = false;
			results.add(errorResult);
			return results;
		}

		if (!invalidRiskCases.isEmpty()) {
			logFedExError('FedExBulkLabelProcessor.generateLabel', 'Risk of Loss is missing for Cases: ' + String.join(invalidRiskCases, ', '), String.valueOf(caseIds));
			BulkLabelResult errorResult = new BulkLabelResult();
			errorResult.message = '❌ Risk of Loss is missing for Cases: ' + String.join(invalidRiskCases, ', ');
			errorResult.isSuccess = false;
			results.add(errorResult);
			return results;
		}

		for (Case c: allCases) {
			if (String.isBlank(c.Brand_Name__c) || c.Brand_Name__c == 'None') {
				invalidCaseNumbers.add(c.CaseNumber);
			}
		}

		if (!invalidCaseNumbers.isEmpty()) {
			logFedExError('FedExBulkLabelProcessor.generateLabel', 'Brand Name is missing or invalid for Cases: ' + String.join(invalidCaseNumbers, ', '), String.valueOf(caseIds));
			BulkLabelResult errorResult = new BulkLabelResult();
			errorResult.message = '❌ Brand Name is missing or invalid for Cases: ' + String.join(invalidCaseNumbers, ', ');
			errorResult.isSuccess = false;
			results.add(errorResult);
			return results; // stop execution since error found
		}
		// Collect all Case Ids
		Set<Id> allCaseIds = new Set<Id>();
		for (Case c: allCases) {
			allCaseIds.add(c.Id);
		}

		List<Label__c> allCaseLabels = [
			SELECT Id FROM Label__c
			WHERE Case__c IN: allCaseIds
		];

		if (allCaseLabels.isEmpty()) {
			BulkLabelResult successResult = new BulkLabelResult();
			successResult.message = '✅ No Label__c records exist for given Cases. Nothing to process.';
			successResult.isSuccess = true;
			results.add(successResult);
			return results;
		}

		// Step 3: Find Label__c records without Master_Tracking_Number__c
		List<Label__c> labels = [
			SELECT Id, Name, Case__c, Master_Tracking_Number__c, Packaging_Type__c, Pickup_Type__c, 
				Service_Type__c, Address__Street__s, Address__City__s, Address__PostalCode__s, 
				Address__StateCode__s, Address__CountryCode__s, Ship_Date_Stamp__c, Units__c, 
				Value__c, Account__c, Use_Ship_Date_Stamp__c, IncludeCustomsClearanceDetail__c,
            	Case__r.Brand_Name__c
			FROM Label__c
			WHERE Case__c IN: allCaseIds AND (
				Master_Tracking_Number__c = NULL OR Master_Tracking_Number__c = ''
			)
		];

		if (labels.isEmpty()) {
			logFedExError('FedExBulkLabelProcessor.generateLabel', 'No Label__c records without tracking numbers found.', String.valueOf(caseIds));
			BulkLabelResult errorResult = new BulkLabelResult();
			errorResult.message = 'ℹ️ No Label__c records without tracking numbers found.';
			errorResult.isSuccess = false;
			results.add(errorResult);
			return results;
		}

		// Get Account data for all labels
		Set<Id> accountIds = new Set<Id>();
		for (Label__c lbl: labels) {
			if (lbl.Account__c != null) {
				accountIds.add(lbl.Account__c);
			}
		}

		Map<Id, Account> accountMap = new Map<Id, Account>([
			SELECT Id, Name, Phone, BillingStreet, BillingCity, BillingState, BillingPostalCode
			FROM Account
			WHERE Id IN: accountIds
		]);

		// Get FedEx Config
		FedEx_Config__mdt config = [
			SELECT MasterLabel FROM FedEx_Config__mdt LIMIT 1
		];

		// Process each label and collect data for batch operations
		List<LabelProcessingData> processingDataList = new List<LabelProcessingData>();

		// ✅ Step 1: Group Labels by Address
		Map<String, List<Label__c>> addressToLabelsMap = new Map<String, List<Label__c>>();

		for (Label__c lbl: labels) {
			String addressKey = lbl.Address__Street__s + '|' + 
				lbl.Address__City__s + '|' + 
				lbl.Address__StateCode__s + '|' + 
				lbl.Address__PostalCode__s + '|' + 
				lbl.Address__CountryCode__s;

			if (!addressToLabelsMap.containsKey(addressKey)) {
				addressToLabelsMap.put(addressKey, new List<Label__c>());
			}
			addressToLabelsMap.get(addressKey).add(lbl);
		}

		// ✅ Step 2: Process unique addresses only
		for (String addrKey: addressToLabelsMap.keySet()) {
			List<Label__c> sameAddressLabels = addressToLabelsMap.get(addrKey);
			Label__c firstLabel = sameAddressLabels[0]; // sirf ek representative label use karenge

			try {
				Account acc = accountMap.get(firstLabel.Account__c);
				if (acc == null) {
					logFedExError('FedExBulkLabelProcessor.generateLabel', 'Account not found for Label: ' + firstLabel.Id, String.valueOf(firstLabel.Id));
					BulkLabelResult errorResult = new BulkLabelResult();
					errorResult.message = '❌ Account not found for Label: ' + firstLabel.Id;
					errorResult.isSuccess = false;
					results.add(errorResult);
					continue;
				}

				// ✅ Sirf ek hi API callout per unique address
				String response = createShipmentCallout(firstLabel, acc, config, flowPONumber);

				// ✅ Parse response
				LabelProcessingData processData = parseShipmentResponse(firstLabel.Id, response, firstLabel.Name);
				if (processData != null) {
					processingDataList.add(processData);

					// ✅ Us address ke sare labels ke liye tracking number update karna
					for (Label__c lbl: sameAddressLabels) {
						BulkLabelResult successResult = new BulkLabelResult();
						successResult.message = '✅ Label processed successfully for: ' + lbl.Id;
						successResult.isSuccess = true;
						successResult.labelId = lbl.Id;
						successResult.trackingNumber = processData.trackingNumber;
						results.add(successResult);
					}

				} else {
					for (Label__c lbl: sameAddressLabels) {
						logFedExError('FedExBulkLabelProcessor.generateLabel', 'Failed to process Label: ' + lbl.Id + ' Response: ' + response, String.valueOf(lbl.Id));
						BulkLabelResult errorResult = new BulkLabelResult();
						errorResult.message = '❌ Failed to process Label: ' + lbl.Id;
						errorResult.isSuccess = false;
						errorResult.labelId = lbl.Id;
						results.add(errorResult);
					}
				}

			} catch(Exception ex) {
				for (Label__c lbl: sameAddressLabels) {
					logFedExError('FedExBulkLabelProcessor.generateLabel', 'Error processing Label ' + lbl.Id + ': ' + ex.getMessage(), String.valueOf(lbl.Id));
					BulkLabelResult errorResult = new BulkLabelResult();
					errorResult.message = '❌ Error processing Label ' + lbl.Id + ': ' + ex.getMessage();
					errorResult.isSuccess = false;
					errorResult.labelId = lbl.Id;
					results.add(errorResult);
				}
			}
		}

		// Batch process all successful labels (DML operations)
		System.debug('🔍 Processing data list size: ' + processingDataList.size());
		if (!processingDataList.isEmpty()) {
			List<String> contentVersionIds = processBatchDMLOperations(processingDataList);
			System.debug('📁 ContentVersion IDs created: ' + contentVersionIds);

			// Add ContentVersion IDs collection to the FIRST result
			if (!contentVersionIds.isEmpty() && !results.isEmpty()) {
				results[0].contentVersionIds = contentVersionIds;
				// Update first result message to include ContentVersion info
				results[0].message = results[0].message + ' | 📁 ' + contentVersionIds.size() + ' ContentVersions created';
				System.debug('✅ Added ContentVersion IDs to first result: ' + results[0].contentVersionIds);
			} else {
				System.debug('⚠️ No ContentVersion IDs to add or no results available');
			}
		} else {
			System.debug('⚠️ Processing data list is empty - no DML operations to perform');
		}

		return results;
	}

	public static String createShipmentCallout(Label__c lbl, Account acc, FedEx_Config__mdt config, String poNumber) {
	
		Date shipDatestamp = lbl.Use_Ship_Date_Stamp__c && lbl.Ship_Date_Stamp__c != null
			? lbl.Ship_Date_Stamp__c
			: System.today();

		String weightUnit = String.isBlank(lbl.Units__c)
			? 'LB' 
			: lbl.Units__c;
			
		Decimal weightValue = (lbl.Value__c == null || lbl.Value__c < 1) 
			? 1 
			: lbl.Value__c;
		
        String brandName = lbl.Case__r.Brand_Name__c;
        
        Boolean includeCustomsClearanceDetail = lbl.IncludeCustomsClearanceDetail__c == true;

		// Prepare request JSON
		Map<String, Object> body = new Map<String, Object>();
		body.put('labelResponseOptions', 'LABEL');

		Map<String, Object> shipment = new Map<String, Object>();

		// Shipper
		Map<String, Object> shipper = new Map<String, Object>();
		shipper.put('contact', new Map<String, Object>{
			'personName' => acc.Name,
			'phoneNumber' => acc.Phone
		});
		shipper.put('address', new Map<String, Object>{
			'streetLines' => new List<String>{ lbl.Address__Street__s },
			'city' => lbl.Address__City__s,
			'stateOrProvinceCode' => lbl.Address__StateCode__s,
			'postalCode' => lbl.Address__PostalCode__s,
			'countryCode' => lbl.Address__CountryCode__s
		});
		shipment.put('shipper', shipper);

		// Recipient
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
		shipment.put('recipients', new List<Object>{ recipient });

		// Other Shipment Data

		shipment.put('shipDatestamp', String.valueOf(shipDatestamp));
		shipment.put('serviceType', lbl.Service_Type__c);
		shipment.put('packagingType', lbl.Packaging_Type__c);
		shipment.put('pickupType', lbl.Pickup_Type__c);
		shipment.put('blockInsightVisibility', false);

		shipment.put('shippingChargesPayment', new Map<String, Object>{
			'paymentType' => 'SENDER'
		});

		shipment.put('labelSpecification', new Map<String, Object>{
			'imageType' => 'PDF',
			'labelStockType' => 'PAPER_85X11_TOP_HALF_LABEL'
		});

		// Declared Value (insuredValue replaced with declaredValue for correct mapping)
		Map<String, Object> declaredValue = new Map<String, Object>{
			'amount' => 500,
			'currency' => 'USD'
		};

		// Package weight
		Map<String, Object> packageWeight = new Map<String, Object>{
			'units' => weightUnit,
			'value' => weightValue
		};

		// ✅ Add Customer Reference for PO Number
		List<Object> customerReferences = new List<Object>();
		if (String.isNotBlank(poNumber)) {
			customerReferences.add(new Map<String, Object>{
				'customerReferenceType' => 'P_O_NUMBER',
				'value' => poNumber
			});
		}

		// Package Line Item
		Map<String, Object> packageLineItem = new Map<String, Object>{
			'weight' => packageWeight,
			'declaredValue' => declaredValue
		};

		// Only add customerReferences if PO number exists
		if (!customerReferences.isEmpty()) {
			packageLineItem.put('customerReferences', customerReferences);
		}

		shipment.put('requestedPackageLineItems', new List<Object>{ packageLineItem });

        Map<String, Object> customsClearanceDetail = new Map<String, Object>{
            'dutiesPayment' => new Map<String, Object>{
                'paymentType' => 'RECIPIENT',
                'payor' => new Map<String, Object>{
                    'responsibleParty' => new Map<String, Object>{
                        'accountNumber' => new Map<String, Object>{
                            'value' => config.MasterLabel
                        }
                    }
                }
            },
            'commercialInvoice' => new Map<String, Object>{
                'shipmentPurpose' => 'NOT_SOLD'
            },
            'commodities' => new List<Object>{
                new Map<String, Object>{
                    'description' => String.format('Item of {0} for inspection/evaluation (not sold)', new List<String>{ brandName }),
                    'countryOfManufacture' => 'US',
                    'quantity' => 1,
                    'quantityUnits' => 'EA',
                    'unitPrice' => new Map<String, Object>{
                        'amount' => 500,
                        'currency' => 'USD'
                    },
                    'customsValue' => new Map<String, Object>{
                        'amount' => 500,
                        'currency' => 'USD'
                    },
                    'weight' => new Map<String, Object>{
                        'units' => weightUnit,
                        'value' => weightValue
                    },
                    'additionalMeasures' => new List<Object>{
                        new Map<String, Object>{
                            'quantity' => 1,
                            'units' => 'EA'
                        }
                    }
                }
            },
            'totalCustomsValue' => new Map<String, Object>{
                'amount' => 500,
                'currency' => 'USD'
            }
        };

        if(includeCustomsClearanceDetail) shipment.put('customsClearanceDetail', customsClearanceDetail);

		body.put('requestedShipment', shipment);
		body.put('accountNumber', new Map<String, Object>{ 'value' => config.MasterLabel });

		String jsonBody = JSON.serialize(body);

		// Make HTTP callout
		FedEx_Config__mdt fedexConfig = [
			SELECT Environment__c FROM FedEx_Config__mdt LIMIT 1
		];

		String baseUrl = (fedexConfig.Environment__c == 'Sandbox')
			? 'https://apis-sandbox.fedex.com'
			: 'https://apis.fedex.com';

		String accessToken = FedExAuthService.getAccessToken();

		Http http = new Http();
		HttpRequest req = new HttpRequest();
		req.setEndpoint(baseUrl + '/ship/v1/shipments');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'application/json');
		req.setHeader('Authorization', 'Bearer ' + accessToken);
		req.setBody(jsonBody);

		HttpResponse res = http.send(req);
		String responseBody = res.getBody();

		System.debug('shipments::request-body' + jsonBody);
		System.debug('shipments::response-body' + responseBody);

		return responseBody;
	}

	public static LabelProcessingData parseShipmentResponse(Id labelId, String responseBody, String labelName) {
		try {
			Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

			if(!responseMap.containsKey('output')) {
				logFedExError('FedExBulkLabelProcessor.parseShipmentResponse', 'FedEx shipment response did not contain output: ' + responseBody, String.valueOf(labelId));
                
                if(responseMap.containsKey('errors')) {

                    List<Object> errors = (List<Object>) responseMap.get('errors');
                    String errorsBody = JSON.serialize(errors);
                    
                    errorsBody = errorsBody.length() > 32767 ? errorsBody.substring(0, 32767) : errorsBody;

                    update new Label__c(
                        Id = labelId,
                        FedeX_Error__c = errorsBody
                    );
                }
                
                return null;
            }

			Map<String, Object> output = (Map<String, Object>) responseMap.get('output');
			List<Object> transactionShipments = (List<Object>) output.get('transactionShipments');

			if (transactionShipments.isEmpty()) return null;
			
			Map<String, Object> shipments = (Map<String, Object>) transactionShipments[0];
			String trackingNum = (String) shipments.get('masterTrackingNumber');

			if (String.isBlank(trackingNum)) return null;

			List<Object> pieceResponses = (List<Object>) shipments.get('pieceResponses');

			if (pieceResponses.isEmpty()) return null;

			Map<String, Object> pieceResp = (Map<String, Object>) pieceResponses[0];
			List<Object> packageDocs = (List<Object>) pieceResp.get('packageDocuments');

			if (packageDocs.isEmpty()) return null;

			Map<String, Object> packageDoc = (Map<String, Object>) packageDocs[0];
			String base64Label = (String) packageDoc.get('encodedLabel');

			if (String.isBlank(base64Label)) return null;

			LabelProcessingData processData = new LabelProcessingData();
			processData.labelId = labelId;
			processData.trackingNumber = trackingNum;
			processData.base64Label = base64Label;
			processData.labelName = labelName;
			return processData;

		} catch(Exception e) {
			// Log error but don't throw
			logFedExError('FedExBulkLabelProcessor.parseShipmentResponse', 'Error parsing response: ' + e.getMessage(), String.valueOf(labelId));
		}

		return null;
	}

	public static List<String> processBatchDMLOperations(List<LabelProcessingData> processingDataList) {
		List<ContentVersion> contentVersionsToInsert = new List<ContentVersion>();
		List<Label__c> labelsToUpdate = new List<Label__c>();
		List<String> contentVersionIds = new List<String>();

		Map<Id, Id> labelToCaseMap = new Map<Id, Id>();

		// Step 1: Prepare ContentVersions aur Labels
		for (LabelProcessingData data: processingDataList) {
			Label__c lbl = [
				SELECT Id, Case__c FROM Label__c
				WHERE Id = :data.labelId
				LIMIT 1
			];

			if (lbl.Case__c != null) {
				labelToCaseMap.put(data.labelId, lbl.Case__c);
			}

			contentVersionsToInsert.add(new ContentVersion(
				Title = 'FedEx Label - ' + data.labelName,
				PathOnClient = 'FedExLabel_' + data.labelName + '.pdf',
				VersionData = EncodingUtil.base64Decode(data.base64Label),
				Origin = 'H'
			));

			labelsToUpdate.add(new Label__c(
				Id = data.labelId, 
				Master_Tracking_Number__c = data.trackingNumber
			));
		}

		try {
			// Step 2: Insert ContentVersions
			insert contentVersionsToInsert;

			// Step 3: Map ContentVersions back to Cases
			List<ContentVersion> insertedVersions = [
				SELECT Id, ContentDocumentId FROM ContentVersion
				WHERE Id IN: contentVersionsToInsert
			];

			List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();

			Integer idx = 0;
			for (ContentVersion cv: insertedVersions) {
				LabelProcessingData data = processingDataList[idx];
				Id caseId = labelToCaseMap.get(data.labelId);

				if (caseId != null) {
					linksToInsert.add(new ContentDocumentLink(
						ContentDocumentId = cv.ContentDocumentId, 
						LinkedEntityId = caseId, 
						ShareType = 'V', 
						Visibility = 'AllUsers'
					));
				}

				contentVersionIds.add(cv.Id);
				idx++;
			}

			if (!linksToInsert.isEmpty()) {
				insert linksToInsert;
			}

			// Step 4: Update Labels
			if (!labelsToUpdate.isEmpty()) {
				update labelsToUpdate;
			}

		} catch(Exception e) {
			logFedExError('FedExBulkLabelProcessor.processBatchDMLOperations', 'Error in batch DML operations: ' + e.getMessage(), null);
		}

		return contentVersionIds;
	}

	// Inner classes for data structure
	public class LabelProcessingData {
		public Id labelId;
		public String trackingNumber;
		public String base64Label;
		public String labelName; // Add this line
	}
	
	global class BulkLabelResult {
		@InvocableVariable
		global String message;

		@InvocableVariable
		global Boolean isSuccess;

		@InvocableVariable
		global String labelId;

		@InvocableVariable
		global String trackingNumber;

		@InvocableVariable
		global String errorMessage;

		@InvocableVariable
		global String contentVersionId;

		@InvocableVariable
		global List<String> contentVersionIds;
	}

	private static void logFedExError(String classMethodName, String message, String relatedId) {
		ErrorLogUtility.logPaymentError('FedEx', classMethodName, message, relatedId);
	}
}
