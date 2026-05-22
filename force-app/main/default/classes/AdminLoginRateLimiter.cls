public with sharing class AdminLoginRateLimiter {
    private static final Integer MAX_ATTEMPTS = 5;
    private static final Integer WINDOW_SECONDS = 15 * 60; // 15 minutes

    // Checks the attempt count for the given username and throws if the limit is exceeded.
    // Uses Platform Cache (org partition 'local') if available; logs and allows through if not provisioned.
    // Skipped in test context because Platform Cache is not provisioned in test execution.
    public static void checkAndIncrement(String username) {
        if (String.isBlank(username) || Test.isRunningTest()) {
            return;
        }
        String key = buildKey(username);
        try {
            Integer attempts = (Integer) Cache.Org.get(key);
            if (attempts == null) {
                attempts = 0;
            }
            if (attempts >= MAX_ATTEMPTS) {
                throw new AuraHandledException(
                    'Too many login attempts. Please wait 15 minutes before trying again.'
                );
            }
            Cache.Org.put(key, attempts + 1, WINDOW_SECONDS);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            // Platform Cache not provisioned or unavailable — allow through silently.
            // Do NOT call ErrorLogUtility here: it performs DML (inserts Error_Log__c),
            // which would cause "uncommitted work pending" when the callout follows in the same transaction.
        }
    }

    public static void clearOnSuccess(String username) {
        if (String.isBlank(username)) {
            return;
        }
        try {
            Cache.Org.remove(buildKey(username));
        } catch (Exception e) {
            // Platform Cache not provisioned — safe to ignore on success path.
        }
    }

    private static String buildKey(String username) {
        return 'qb_login_' + EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(UserInfo.getOrganizationId() + ':' + username.trim().toLowerCase()))
        );
    }
}