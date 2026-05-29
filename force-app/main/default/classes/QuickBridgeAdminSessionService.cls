public with sharing class QuickBridgeAdminSessionService {
    public class AdminSessionException extends Exception {}

    public class SessionCreateResult {
        @AuraEnabled public String sessionToken { get; set; }
        @AuraEnabled public Datetime sessionExpiresAt { get; set; }
    }

    private static final Integer TOKEN_LENGTH = 64;

    public static SessionCreateResult createSession(String username, Datetime expiresAt) {
        if (String.isBlank(username)) {
            throw new AdminSessionException('Username is required to create an admin session.');
        }
        Datetime expiry = expiresAt == null ? System.now().addHours(8) : expiresAt;
        String rawToken = newRawToken(username);
        String tokenHash = hashToken(rawToken);

        insert new QuickBridge_Admin_Session__c(
            Username__c = username.trim(),
            Token_Hash__c = tokenHash,
            Status__c = 'Active',
            Expires_At__c = expiry,
            Last_Used_At__c = System.now()
        );

        SessionCreateResult result = new SessionCreateResult();
        result.sessionToken = rawToken;
        result.sessionExpiresAt = expiry;
        return result;
    }

    public static QuickBridge_Admin_Session__c requireValidSession(String rawToken) {
        if (String.isBlank(rawToken)) {
            throw new AdminSessionException('QuickBridge admin session is required. Please log in again.');
        }

        String tokenHash = hashToken(rawToken);
        List<QuickBridge_Admin_Session__c> sessions = [
            SELECT Id, Token_Hash__c, Username__c, Status__c, Expires_At__c, Last_Used_At__c, Revoked_At__c
            FROM QuickBridge_Admin_Session__c
            WHERE Token_Hash__c = :tokenHash
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            throw new AdminSessionException('QuickBridge admin session is invalid. Please log in again.');
        }

        QuickBridge_Admin_Session__c sessionRecord = sessions[0];
        if (sessionRecord.Status__c != 'Active') {
            throw new AdminSessionException('QuickBridge admin session is no longer active. Please log in again.');
        }
        if (sessionRecord.Expires_At__c != null && sessionRecord.Expires_At__c <= System.now()) {
            update new QuickBridge_Admin_Session__c(
                Id = sessionRecord.Id,
                Status__c = 'Expired',
                Last_Used_At__c = System.now()
            );
            throw new AdminSessionException('QuickBridge admin session expired. Please log in again.');
        }

        update new QuickBridge_Admin_Session__c(
            Id = sessionRecord.Id,
            Last_Used_At__c = System.now()
        );
        return sessionRecord;
    }

    @AuraEnabled
    public static Boolean revokeSession(String sessionToken) {
        if (String.isBlank(sessionToken)) {
            return false;
        }
        String tokenHash = hashToken(sessionToken);
        List<QuickBridge_Admin_Session__c> sessions = [
            SELECT Id
            FROM QuickBridge_Admin_Session__c
            WHERE Token_Hash__c = :tokenHash
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            return false;
        }
        update new QuickBridge_Admin_Session__c(
            Id = sessions[0].Id,
            Status__c = 'Revoked',
            Revoked_At__c = System.now(),
            Last_Used_At__c = System.now()
        );
        return true;
    }

    @TestVisible
    static String hashToken(String rawToken) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(rawToken == null ? '' : rawToken)));
    }

    private static String newRawToken(String username) {
        String seed = username + ':' + UserInfo.getOrganizationId() + ':' + UserInfo.getUserId() + ':' +
            String.valueOf(System.now().getTime()) + ':' + String.valueOf(Crypto.getRandomInteger()) + ':' +
            String.valueOf(Limits.getCpuTime());
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-512', Blob.valueOf(seed))).left(TOKEN_LENGTH);
    }
}