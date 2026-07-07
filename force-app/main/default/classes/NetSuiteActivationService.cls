public with sharing class NetSuiteActivationService {
  public class SetupRequest {
    public String accountId;
    public String environment;
    public String restWebServicesUrl;
    public String suiteqlUrl;
    public String namedCredentialName;
    public String externalCredentialName;
    public String authType;
    public String consumerKeyReference;
    public String consumerSecretReference;
    public String tokenIdReference;
    public String tokenSecretReference;
    public Integer pollingIntervalMinutes;
  }

  public class ActivationResult {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public List<String> messages { get; set; }
    @AuraEnabled public List<String> warnings { get; set; }

    public ActivationResult() {
      success = true;
      messages = new List<String>();
      warnings = new List<String>();
    }
  }

  private static final String CONNECTOR_KEY = 'netsuite';
  private static final Set<String> REQUIRED_PHASE_ONE_FIELDS = new Set<String>{
    'account_id',
    'environment',
    'rest_web_services_url',
    'suiteql_url',
    'named_credential_name',
    'auth_type',
    'enable_customer_sync',
    'enable_item_sync',
    'polling_interval_minutes'
  };
  private static final Set<String> SECRET_REFERENCE_FIELDS = new Set<String>{
    'consumer_key_reference',
    'consumer_secret_reference',
    'token_id_reference',
    'token_secret_reference'
  };

  public static SetupRequest templateRequest() {
    SetupRequest request = new SetupRequest();
    request.accountId = 'REPLACE_WITH_NETSUITE_ACCOUNT_ID';
    request.environment = 'Sandbox';
    request.restWebServicesUrl = 'REPLACE_WITH_NETSUITE_REST_WEB_SERVICES_URL';
    request.suiteqlUrl = '/services/rest/query/v1/suiteql';
    request.namedCredentialName = 'REPLACE_WITH_NETSUITE_NAMED_CREDENTIAL';
    request.externalCredentialName = 'REPLACE_WITH_NETSUITE_EXTERNAL_CREDENTIAL';
    request.authType = 'TBA';
    request.consumerKeyReference = 'REPLACE_WITH_NETSUITE_CONSUMER_KEY_REFERENCE';
    request.consumerSecretReference = 'REPLACE_WITH_NETSUITE_CONSUMER_SECRET_REFERENCE';
    request.tokenIdReference = 'REPLACE_WITH_NETSUITE_TOKEN_ID_REFERENCE';
    request.tokenSecretReference = 'REPLACE_WITH_NETSUITE_TOKEN_SECRET_REFERENCE';
    request.pollingIntervalMinutes = 60;
    return request;
  }

  public static ActivationResult setupPhaseOne(SetupRequest request) {
    ActivationResult result = new ActivationResult();
    SetupRequest effective = request == null ? templateRequest() : request;

    Connector_Instance__c instanceRecord = loadInstance();
    if (instanceRecord == null) {
      instanceRecord = new Connector_Instance__c();
      instanceRecord.Name = 'NetSuite';
      result.messages.add('Created NetSuite connector instance.');
    } else {
      result.messages.add('Updated existing NetSuite connector instance.');
    }
    instanceRecord.Connector_Key__c = CONNECTOR_KEY;
    instanceRecord.Connector_Label__c = 'NetSuite';
    instanceRecord.Active__c = true;
    instanceRecord.Health_Status__c = String.isBlank(instanceRecord.Health_Status__c)
      ? 'Unknown'
      : instanceRecord.Health_Status__c;
    instanceRecord.Entitlement_Status__c = String.isBlank(instanceRecord.Entitlement_Status__c)
      ? 'Active'
      : instanceRecord.Entitlement_Status__c;
    instanceRecord.Environment__c = firstNonBlank(effective.environment, 'Sandbox');
    instanceRecord.Named_Credential__c = effective.namedCredentialName;
    instanceRecord.External_Credential__c = effective.externalCredentialName;
    upsert instanceRecord;

    Map<String, String> values = phaseOneValues(effective);
    Map<String, Connector_Config_Value__c> existingByField = existingValues(instanceRecord.Id);
    List<Connector_Config_Value__c> rows = new List<Connector_Config_Value__c>();
    for (String fieldKey : values.keySet()) {
      Connector_Config_Value__c row = existingByField.containsKey(fieldKey)
        ? existingByField.get(fieldKey)
        : new Connector_Config_Value__c();
      row.Name = CONNECTOR_KEY + ':' + fieldKey;
      row.Connector_Instance__c = instanceRecord.Id;
      row.Connector_Key__c = CONNECTOR_KEY;
      row.Field_Key__c = fieldKey;
      row.Value__c = values.get(fieldKey);
      row.Is_Secret_Reference__c = SECRET_REFERENCE_FIELDS.contains(fieldKey);
      rows.add(row);
    }
    upsert rows;
    result.messages.add('Seeded ' + rows.size() + ' NetSuite connector config value row(s).');
    result.warnings.add('Replace any REPLACE_WITH_ placeholder values before enabling live NetSuite traffic.');
    return result;
  }

  public static ActivationResult validatePhaseOne() {
    ActivationResult result = new ActivationResult();
    List<Connector_Instance__c> instances = [
      SELECT Id, Active__c, Named_Credential__c, External_Credential__c
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :CONNECTOR_KEY
    ];
    if (instances.size() != 1) {
      addFailure(
        result,
        'Expected exactly one Connector_Instance__c row for Connector_Key__c = netsuite, found ' + instances.size() + '.'
      );
      return result;
    }
    Connector_Instance__c instanceRecord = instances[0];
    if (instanceRecord.Active__c != true) {
      addFailure(result, 'NetSuite Connector_Instance__c row is not active.');
    }
    if (String.isBlank(instanceRecord.Named_Credential__c)) {
      addFailure(result, 'NetSuite Connector_Instance__c is missing Named_Credential__c.');
    }

    Map<String, Connector_Config_Value__c> valuesByField = new Map<String, Connector_Config_Value__c>();
    for (Connector_Config_Value__c valueRecord : [
      SELECT Field_Key__c, Value__c, Is_Secret_Reference__c
      FROM Connector_Config_Value__c
      WHERE Connector_Key__c = :CONNECTOR_KEY
    ]) {
      valuesByField.put(valueRecord.Field_Key__c, valueRecord);
      String value = String.valueOf(valueRecord.Value__c);
      if (value != null && value.startsWith('REPLACE_WITH_')) {
        addFailure(result, 'Placeholder value remains for NetSuite config field ' + valueRecord.Field_Key__c + '.');
      }
      if (
        SECRET_REFERENCE_FIELDS.contains(valueRecord.Field_Key__c) &&
        valueRecord.Is_Secret_Reference__c != true
      ) {
        addFailure(result, 'NetSuite config field ' + valueRecord.Field_Key__c + ' is not marked as a secret reference.');
      }
    }

    Set<String> missingFields = new Set<String>(REQUIRED_PHASE_ONE_FIELDS);
    missingFields.removeAll(valuesByField.keySet());
    for (String fieldKey : valuesByField.keySet()) {
      if (
        REQUIRED_PHASE_ONE_FIELDS.contains(fieldKey) &&
        String.isBlank(String.valueOf(valuesByField.get(fieldKey).Value__c))
      ) {
        missingFields.add(fieldKey);
      }
    }
    if (!missingFields.isEmpty()) {
      addFailure(result, 'Missing NetSuite config fields: ' + String.join(new List<String>(missingFields), ', ') + '.');
    }

    if (result.success == true) {
      result.messages.add('NetSuite Phase 1 runtime configuration is present.');
    }
    return result;
  }

  private static Connector_Instance__c loadInstance() {
    List<Connector_Instance__c> existing = [
      SELECT Id, Name, Health_Status__c, Entitlement_Status__c
      FROM Connector_Instance__c
      WHERE Connector_Key__c = :CONNECTOR_KEY
      LIMIT 1
    ];
    return existing.isEmpty() ? null : existing[0];
  }

  private static Map<String, Connector_Config_Value__c> existingValues(Id instanceId) {
    Map<String, Connector_Config_Value__c> existingByField = new Map<String, Connector_Config_Value__c>();
    for (Connector_Config_Value__c row : [
      SELECT Id, Field_Key__c
      FROM Connector_Config_Value__c
      WHERE Connector_Instance__c = :instanceId
    ]) {
      existingByField.put(row.Field_Key__c, row);
    }
    return existingByField;
  }

  private static Map<String, String> phaseOneValues(SetupRequest request) {
    return new Map<String, String>{
      'account_id' => request.accountId,
      'environment' => firstNonBlank(request.environment, 'Sandbox'),
      'rest_web_services_url' => request.restWebServicesUrl,
      'suiteql_url' => firstNonBlank(request.suiteqlUrl, '/services/rest/query/v1/suiteql'),
      'named_credential_name' => request.namedCredentialName,
      'auth_type' => firstNonBlank(request.authType, 'TBA'),
      'consumer_key_reference' => request.consumerKeyReference,
      'consumer_secret_reference' => request.consumerSecretReference,
      'token_id_reference' => request.tokenIdReference,
      'token_secret_reference' => request.tokenSecretReference,
      'enable_customer_sync' => 'true',
      'enable_item_sync' => 'true',
      'enable_sales_order_sync' => 'false',
      'enable_invoice_sync' => 'false',
      'enable_payment_sync' => 'false',
      'enable_fulfillment_sync' => 'false',
      'polling_interval_minutes' => String.valueOf(request.pollingIntervalMinutes == null ? 60 : request.pollingIntervalMinutes),
      'webhook_enabled' => 'false'
    };
  }

  private static void addFailure(ActivationResult result, String message) {
    result.success = false;
    result.messages.add(message);
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isBlank(firstValue) ? secondValue : firstValue;
  }
}