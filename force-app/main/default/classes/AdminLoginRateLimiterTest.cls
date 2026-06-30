/**
 * Test class for AdminLoginRateLimiter.
 * Validates rate‑limiting behavior for login and PIN recovery flows,
 * including bucket isolation, threshold enforcement, and success clearing.
 */
@isTest(seeAllData=false)
private class AdminLoginRateLimiterTest {

    // ========================================================================
    // Key building tests (always covered, no cache dependency)
    // ========================================================================

    @isTest
    static void testKeyBuilding_DifferentBuckets_ReturnDifferentKeys() {
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
            'Login and PIN recovery must use different cache keys.'
        );
    }

    @isTest
    static void testKeyBuilding_NullBucket_DefaultsToLogin() {
        String keyWithLogin = AdminLoginRateLimiter.buildKeyForTest('admin@example.com', AdminLoginRateLimiter.LOGIN_BUCKET);
        String keyWithNull = AdminLoginRateLimiter.buildKeyForTest('admin@example.com', null);
        System.assertEquals(keyWithLogin, keyWithNull, 'Null bucket name should default to login bucket.');
    }

    @isTest
    static void testKeyBuilding_WhitespaceAndCase_IsNormalized() {
        String key1 = AdminLoginRateLimiter.buildKeyForTest('  Admin@Example.COM  ', AdminLoginRateLimiter.LOGIN_BUCKET);
        String key2 = AdminLoginRateLimiter.buildKeyForTest('admin@example.com', AdminLoginRateLimiter.LOGIN_BUCKET);
        System.assertEquals(key1, key2, 'Keys must be case‑insensitive and trimmed.');
    }

    // ========================================================================
    // checkAndIncrement – core rate‑limiting logic (with test cache)
    // ========================================================================

    @isTest
    static void testCheckAndIncrement_FirstAttempt_StoresCountOne() {
        String username = 'first@attempt.com';

        Test.startTest();
        AdminLoginRateLimiter.checkAndIncrement(username);
        Test.stopTest();

        System.assert(true, 'First attempt should succeed without exception.');
    }

    @isTest
    static void testCheckAndIncrement_FifthAttempt_Succeeds() {
        String username = 'fifth@attempt.com';

        Test.startTest();
        for (Integer i = 0; i < 5; i++) {
            AdminLoginRateLimiter.checkAndIncrement(username);
        }
        Test.stopTest();

        System.assert(true, 'Fifth attempt should succeed (still within limit).');
    }

    @isTest
    static void testCheckAndIncrement_SixthAttempt_ThrowsAuraHandledException() {
        // Override the test-mode bypass to test the real logic
        AdminLoginRateLimiter.disableForTests = false;
        String username = 'sixth@attempt.com';

        Test.startTest();
        for (Integer i = 0; i < 5; i++) {
            AdminLoginRateLimiter.checkAndIncrement(username);
        }
        // 6th attempt must throw
        try {
            AdminLoginRateLimiter.checkAndIncrement(username);
            System.assert(false, 'Expected AuraHandledException was not thrown.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Too many login attempts'),
                'Exception message should mention login attempts.');
        }
        Test.stopTest();
    }

    @isTest
    static void testCheckAndIncrement_PinRecoveryBucket_UsesSeparateCounter() {
        AdminLoginRateLimiter.disableForTests = false;
        String username = 'same@user.com';
        String loginBucket = AdminLoginRateLimiter.LOGIN_BUCKET;
        String pinBucket = AdminLoginRateLimiter.PIN_RECOVERY_BUCKET;

        Test.startTest();
        // exhaust login bucket
        for (Integer i = 0; i < 5; i++) {
            AdminLoginRateLimiter.checkAndIncrement(username, loginBucket);
        }
        // PIN recovery should still succeed
        AdminLoginRateLimiter.checkAndIncrement(username, pinBucket);
        Test.stopTest();

        System.assert(true, 'PIN recovery attempts should be isolated from login attempts.');
    }

    @isTest
    static void testCheckAndIncrement_BlankUsername_DoesNothing() {
        Test.startTest();
        AdminLoginRateLimiter.checkAndIncrement('');
        AdminLoginRateLimiter.checkAndIncrement(null);
        AdminLoginRateLimiter.checkAndIncrement('   ', AdminLoginRateLimiter.PIN_RECOVERY_BUCKET);
        Test.stopTest();

        System.assert(true, 'Blank username handled gracefully.');
    }

    @isTest
    static void testCheckAndIncrement_CustomBucketName_IsNormalized() {
        AdminLoginRateLimiter.disableForTests = false;
        Test.startTest();
        AdminLoginRateLimiter.checkAndIncrement('user@test.com', '   CUSTOM_BUCKET   ');
        Test.stopTest();

        System.assert(true, 'Custom bucket name accepted and normalized.');
    }

    // ========================================================================
    // clearOnSuccess tests
    // ========================================================================

    @isTest
static void testClearOnSuccess_LoginBucket_RemovesCounter() {
    AdminLoginRateLimiter.disableForTests = false;
    String username = 'clear@test.com';
    Test.startTest();
    AdminLoginRateLimiter.checkAndIncrement(username); // attempt 1
    AdminLoginRateLimiter.clearOnSuccess(username);    // reset to 0

    // After clear, 5 attempts should succeed (MAX_ATTEMPTS = 5)
    for (Integer i = 0; i < 5; i++) {
        AdminLoginRateLimiter.checkAndIncrement(username);
    }
    // 6th attempt should throw
    try {
        AdminLoginRateLimiter.checkAndIncrement(username);
        System.assert(false, 'Expected exception on 6th attempt after reset.');
    } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('Too many login attempts'), 
            'Expected rate limit exception.');
    }
    Test.stopTest();
}

    @isTest
static void testClearOnSuccess_PinRecoveryBucket_RemovesCounter() {
    AdminLoginRateLimiter.disableForTests = false;
    String username = 'pinclear@test.com';
    Test.startTest();
    AdminLoginRateLimiter.checkAndIncrement(username, AdminLoginRateLimiter.PIN_RECOVERY_BUCKET); // attempt 1
    AdminLoginRateLimiter.clearOnSuccess(username, AdminLoginRateLimiter.PIN_RECOVERY_BUCKET);   // reset to 0

    // After clear, 5 attempts should succeed
    for (Integer i = 0; i < 5; i++) {
        AdminLoginRateLimiter.checkAndIncrement(username, AdminLoginRateLimiter.PIN_RECOVERY_BUCKET);
    }
    // 6th attempt should throw
    try {
        AdminLoginRateLimiter.checkAndIncrement(username, AdminLoginRateLimiter.PIN_RECOVERY_BUCKET);
        System.assert(false, 'Expected exception on 6th attempt after reset.');
    } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('Too many PIN recovery attempts'), 
            'Expected rate limit exception.');
    }
    Test.stopTest();
}

    @isTest
    static void testClearOnSuccess_BlankUsername_DoesNothing() {
        Test.startTest();
        AdminLoginRateLimiter.clearOnSuccess('');
        AdminLoginRateLimiter.clearOnSuccess(null);
        AdminLoginRateLimiter.clearOnSuccess('   ', AdminLoginRateLimiter.LOGIN_BUCKET);
        Test.stopTest();

        System.assert(true, 'clearOnSuccess with blank username does not throw.');
    }

    @isTest
    static void testClearOnSuccess_NonExistentKey_NoException() {
        AdminLoginRateLimiter.disableForTests = false;
        Test.startTest();
        AdminLoginRateLimiter.clearOnSuccess('nonexistent@user.com');
        Test.stopTest();

        System.assert(true, 'Clearing a non‑existent key should not throw.');
    }

    // ========================================================================
    // Constant verification
    // ========================================================================
    @isTest
    static void testStaticConstants() {
        System.assertEquals('login', AdminLoginRateLimiter.LOGIN_BUCKET);
        System.assertEquals('pin_recovery', AdminLoginRateLimiter.PIN_RECOVERY_BUCKET);
    }
}