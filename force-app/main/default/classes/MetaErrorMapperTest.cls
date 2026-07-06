@IsTest
private class MetaErrorMapperTest {
  @IsTest
  static void userMessagesClassifyCommonMetaFailures() {
    System.assert(MetaErrorMapper.userMessage(400, 'malformed webhook').contains('malformed'));
    System.assert(MetaErrorMapper.userMessage(400, 'unknown lead field').contains('field'));
    System.assert(MetaErrorMapper.userMessage(401, 'access token expired').contains('authentication'));
    System.assert(MetaErrorMapper.userMessage(403, 'permission denied').contains('permission'));
    System.assert(MetaErrorMapper.userMessage(404, 'Unsupported get request').contains('not found'));
    System.assert(MetaErrorMapper.userMessage(429, 'rate limit').contains('rate limit'));
    System.assert(MetaErrorMapper.userMessage(500, 'Server unavailable').contains('Server unavailable'));
    System.assertEquals('Meta API request failed.', MetaErrorMapper.userMessage(null, null));
  }

  @IsTest
  static void loggingRedactsSensitiveValues() {
    MetaErrorMapper.logCalloutFailure(
      'MetaErrorMapperTest.loggingRedactsSensitiveValues',
      'access_token=abc123',
      401,
      'callout:Meta_Graph_API/v21.0/me'
    );

    Error_Log__c logRecord = [
      SELECT Gateway_Name__c, Error_Message__c, HTTP_Status_Code__c
      FROM Error_Log__c
      WHERE Gateway_Name__c = 'Meta'
      LIMIT 1
    ];
    System.assertEquals(Decimal.valueOf(401), logRecord.HTTP_Status_Code__c);
    System.assert(!logRecord.Error_Message__c.contains('abc123'));

    try {
      Integer zeroValue = 0;
      Integer divideByZero = 1 / zeroValue;
      System.assertEquals(null, divideByZero);
    } catch (Exception e) {
      MetaErrorMapper.logException('MetaErrorMapperTest.loggingRedactsSensitiveValues', e);
    }
    System.assertEquals(2, [SELECT COUNT() FROM Error_Log__c WHERE Gateway_Name__c = 'Meta']);
  }
}
