@isTest
private class QBIntegrationExceptionTest {
    @isTest
    static void testCustomExceptionType() {
        Boolean didThrow = false;
        try {
            throw new QBIntegrationException('QB exception test');
        } catch (QBIntegrationException e) {
            didThrow = true;
            System.assertEquals('QB exception test', e.getMessage());
        }
        System.assertEquals(true, didThrow);
    }
}