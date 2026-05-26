@IsTest
private class AdminLoginRateLimiterTest {
    @IsTest
    static void loginAndPinRecoveryUseDifferentCacheBuckets() {
        String loginKey = AdminLoginRateLimiter.buildKeyForTest(
            'Admin@Example.com ',
            AdminLoginRateLimiter.LOGIN_BUCKET
        );
        String recoveryKey = AdminLoginRateLimiter.buildKeyForTest(
            ' admin@example.com',
            AdminLoginRateLimiter.PIN_RECOVERY_BUCKET
        );

        System.assertNotEquals(
            loginKey,
            recoveryKey,
            'Login and PIN recovery attempts must not share the same cache key.'
        );
        System.assertEquals(
            loginKey,
            AdminLoginRateLimiter.buildKeyForTest('admin@example.com', null),
            'Blank bucket names should preserve the legacy login bucket.'
        );
    }
}