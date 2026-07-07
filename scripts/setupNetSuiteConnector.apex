NetSuiteActivationService.SetupRequest request = NetSuiteActivationService.templateRequest();

// Replace these placeholder values before running in a shared org.
request.accountId = 'REPLACE_WITH_NETSUITE_ACCOUNT_ID';
request.environment = 'SANDBOX';
request.restWebServicesUrl = 'https://REPLACE_WITH_ACCOUNT_ID.suitetalk.api.netsuite.com';
request.suiteqlUrl = 'https://REPLACE_WITH_ACCOUNT_ID.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql';
request.namedCredentialName = 'REPLACE_WITH_NETSUITE_NAMED_CREDENTIAL';
request.authType = 'TBA';
request.consumerKeyReference = 'NetSuite_Consumer_Key';
request.consumerSecretReference = 'NetSuite_Consumer_Secret';
request.tokenIdReference = 'NetSuite_Token_Id';
request.tokenSecretReference = 'NetSuite_Token_Secret';
request.pollingIntervalMinutes = 60;

NetSuiteActivationService.ActivationResult result = NetSuiteActivationService.setupPhaseOne(request);

System.debug('NetSuite setup result: ' + JSON.serialize(result));

NetSuiteActivationService.ActivationResult validationResult = NetSuiteActivationService.validatePhaseOne();

if (!validationResult.success) {
  System.debug(LoggingLevel.ERROR, 'NetSuite setup validation failed: ' + JSON.serialize(validationResult));
  System.assert(false, 'NetSuite setup validation failed: ' + String.join(validationResult.messages, ' | '));
}
