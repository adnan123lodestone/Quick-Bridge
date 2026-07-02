public with sharing class MetaWebhookVerifier {
    public static String verifyChallenge(String mode, String verifyToken, String challenge) {
        String expectedToken = MetaConfigService.getValue('webhookVerifyTokenRef');
        if (mode == 'subscribe' && String.isNotBlank(verifyToken) && verifyToken == expectedToken) {
            return challenge;
        }
        throw new MetaWebhookVerificationException('Meta webhook verification token is invalid.');
    }

    public static Boolean isValidSignature(String requestBody, String signatureHeader, String appSecret) {
        if (String.isBlank(requestBody) || String.isBlank(signatureHeader) || String.isBlank(appSecret)) {
            return false;
        }
        String normalized = signatureHeader.trim().toLowerCase();
        if (!normalized.startsWith('sha256=')) {
            return false;
        }
        String providedDigest = normalized.substring('sha256='.length());
        if (String.isBlank(providedDigest)) {
            return false;
        }
        String expectedDigest = EncodingUtil.convertToHex(
            Crypto.generateMac('HmacSHA256', Blob.valueOf(requestBody), Blob.valueOf(appSecret))
        ).toLowerCase();
        return constantTimeEquals(providedDigest, expectedDigest);
    }

    public static void requireValidSignature(String requestBody, RestRequest request) {
        String appSecret = MetaConfigService.getValue('appSecretRef');
        String signatureHeader = getHeaderValue(request, 'X-Hub-Signature-256');
        if (!isValidSignature(requestBody, signatureHeader, appSecret)) {
            throw new MetaWebhookVerificationException('Meta webhook signature verification failed.');
        }
    }

    private static Boolean constantTimeEquals(String leftValue, String rightValue) {
        if (leftValue == null || rightValue == null || leftValue.length() != rightValue.length()) {
            return false;
        }
        Integer diff = 0;
        for (Integer i = 0; i < leftValue.length(); i++) {
            diff = diff | (leftValue.charAt(i) ^ rightValue.charAt(i));
        }
        return diff == 0;
    }

    private static String getHeaderValue(RestRequest request, String headerName) {
        if (request == null || request.headers == null || String.isBlank(headerName)) {
            return null;
        }
        if (request.headers.containsKey(headerName)) {
            return request.headers.get(headerName);
        }
        for (String key : request.headers.keySet()) {
            if (key != null && key.equalsIgnoreCase(headerName)) {
                return request.headers.get(key);
            }
        }
        return null;
    }

    public class MetaWebhookVerificationException extends Exception {}
}