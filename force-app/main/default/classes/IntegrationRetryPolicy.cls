public class IntegrationRetryPolicy {
    public static final Integer DEFAULT_MAX_ATTEMPTS = 5;
    private static final Integer BASE_DELAY_SECONDS = 60;
    private static final Integer MAX_DELAY_SECONDS = 3600;

    public static Integer getMaxAttempts(Integration_Work_Item__c item) {
        if (item != null && item.Max_Attempts__c != null && item.Max_Attempts__c > 0) {
            return Integer.valueOf(item.Max_Attempts__c);
        }
        return DEFAULT_MAX_ATTEMPTS;
    }

    public static Datetime nextAttemptAt(Integer attemptCount) {
        Integer exponent = Math.max(0, Math.min(6, attemptCount == null ? 0 : attemptCount));
        Integer multiplier = 1;
        for (Integer i = 0; i < exponent; i++) {
            multiplier *= 2;
        }
        Integer delay = BASE_DELAY_SECONDS * multiplier;
        if (delay > MAX_DELAY_SECONDS) {
            delay = MAX_DELAY_SECONDS;
        }
        return System.now().addSeconds(delay);
    }

    public static Boolean isRetryable(Exception e) {
        if (e == null || String.isBlank(e.getMessage())) {
            return false;
        }
        return isRetryableMessage(e.getMessage());
    }

    public static Boolean isRetryableMessage(String message) {
        if (String.isBlank(message)) {
            return false;
        }
        String lower = message.toLowerCase();
        return lower.contains('unable_to_lock_row')
            || lower.contains('unable to obtain exclusive access')
            || lower.contains('row lock')
            || lower.contains('timeout')
            || lower.contains('timed out')
            || lower.contains('temporarily unavailable')
            || lower.contains('read timed out');
    }
}
