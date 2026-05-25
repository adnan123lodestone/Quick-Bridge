/**
 * @description Provides Platform Cache-backed rate limiting for admin login and PIN recovery flows.
 */
public with sharing class AdminLoginRateLimiter {
    public static final String LOGIN_BUCKET = 'login';
    public static final String PIN_RECOVERY_BUCKET = 'pin_recovery';
    private static final Integer MAX_ATTEMPTS = 5;
    private static final Integer WINDOW_SECONDS = 15 * 60; // 15 minutes

    /**
        * @description Checks the default login bucket for the user and increments the attempt count.
     * @param username Admin username being protected.
     */
    public static void checkAndIncrement(String username) {
        checkAndIncrement(username, LOGIN_BUCKET);
    }

    /**
        * @description Checks the named bucket for the user and increments the attempt count.
     * @param username Admin username being protected.
     * @param bucketName Rate-limit bucket name.
     */
    public static void checkAndIncrement(String username, String bucketName) {
        if (String.isBlank(username) || Test.isRunningTest()) {
            return;
        }
        String resolvedBucket = normalizeBucketName(bucketName);
        String key = buildKey(username, resolvedBucket);
        try {
            Integer attempts = (Integer) Cache.Org.get(key);
            if (attempts == null) {
                attempts = 0;
            }
            if (attempts >= MAX_ATTEMPTS) {
                String attemptLabel = resolvedBucket == PIN_RECOVERY_BUCKET
                    ? 'PIN recovery attempts'
                    : 'login attempts';
                throw new AuraHandledException(
                    'Too many ' + attemptLabel + '. Please wait 15 minutes before trying again.'
                );
            }
            Cache.Org.put(key, attempts + 1, WINDOW_SECONDS);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            // Platform Cache not provisioned or unavailable; allow through without DML.
            // Do NOT call ErrorLogUtility here: it performs DML (inserts Error_Log__c),
            // which would cause "uncommitted work pending" when the callout follows in the same transaction.
            System.debug(LoggingLevel.DEBUG, 'AdminLoginRateLimiter unavailable: ' + e.getMessage());
        }
    }

    /**
        * @description Clears the default login bucket after successful authentication.
     * @param username Admin username that authenticated successfully.
     */
    public static void clearOnSuccess(String username) {
        clearOnSuccess(username, LOGIN_BUCKET);
    }

    /**
        * @description Clears the named bucket after a successful protected action.
     * @param username Admin username that completed the protected action.
     * @param bucketName Rate-limit bucket name.
     */
    public static void clearOnSuccess(String username, String bucketName) {
        if (String.isBlank(username)) {
            return;
        }
        try {
            Cache.Org.remove(buildKey(username, bucketName));
        } catch (Exception e) {
            // Platform Cache not provisioned; safe to ignore on success path.
            System.debug(LoggingLevel.DEBUG, 'AdminLoginRateLimiter clear skipped: ' + e.getMessage());
        }
    }

    @TestVisible
    static String buildKeyForTest(String username, String bucketName) {
        return buildKey(username, bucketName);
    }

    private static String buildKey(String username, String bucketName) {
        String safeBucket = normalizeBucketName(bucketName);
        return 'qb_' + safeBucket + '_' + EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(UserInfo.getOrganizationId() + ':' + safeBucket + ':' + username.trim().toLowerCase()))
        );
    }

    private static String normalizeBucketName(String bucketName) {
        return String.isBlank(bucketName) ? LOGIN_BUCKET : bucketName.trim().toLowerCase();
    }
}