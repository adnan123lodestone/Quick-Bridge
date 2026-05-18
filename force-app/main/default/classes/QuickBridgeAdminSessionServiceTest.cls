@IsTest
private class QuickBridgeAdminSessionServiceTest {
    @IsTest
    static void createValidateAndRevokeSession() {
        QuickBridgeAdminSessionService.SessionCreateResult created = QuickBridgeAdminSessionService.createSession(
            'admin@example.com',
            System.now().addHours(1)
        );
        System.assertNotEquals(null, created.sessionToken);
        System.assertEquals(64, created.sessionToken.length());
        String tokenHash = QuickBridgeAdminSessionService.hashToken(created.sessionToken);
        System.assertEquals(1, [
            SELECT Count()
            FROM QuickBridge_Admin_Session__c
            WHERE Token_Hash__c = :tokenHash
        ]);

        QuickBridge_Admin_Session__c validated = QuickBridgeAdminSessionService.requireValidSession(created.sessionToken);
        System.assertEquals('admin@example.com', validated.Username__c);

        System.assertEquals(true, QuickBridgeAdminSessionService.revokeSession(created.sessionToken));
        Boolean threw = false;
        try {
            QuickBridgeAdminSessionService.requireValidSession(created.sessionToken);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void expiredAndMissingSessionsFailClosed() {
        QuickBridgeAdminSessionService.SessionCreateResult expired = QuickBridgeAdminSessionService.createSession(
            'admin@example.com',
            System.now().addMinutes(-1)
        );

        Boolean expiredThrew = false;
        try {
            QuickBridgeAdminSessionService.requireValidSession(expired.sessionToken);
        } catch (Exception e) {
            expiredThrew = true;
        }
        System.assertEquals(true, expiredThrew);

        Boolean missingThrew = false;
        try {
            QuickBridgeAdminSessionService.requireValidSession(null);
        } catch (Exception e) {
            missingThrew = true;
        }
        System.assertEquals(true, missingThrew);
    }
}
