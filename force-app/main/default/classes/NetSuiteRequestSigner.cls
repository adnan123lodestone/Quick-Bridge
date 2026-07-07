public with sharing class NetSuiteRequestSigner {
  public class SigningInput {
    public String realm;
    public String consumerKey;
    public String consumerSecret;
    public String tokenId;
    public String tokenSecret;
    public String httpMethod;
    public String url;
    public String nonce;
    public String timestamp;
    public Map<String, String> queryParams;
  }

  public static String authorizationHeader(SigningInput input) {
    if (input == null) {
      throw new NetSuiteRequestSignerException('Signing input is required.');
    }
    requireValue(input.realm, 'realm');
    requireValue(input.consumerKey, 'consumer key');
    requireValue(input.consumerSecret, 'consumer secret');
    requireValue(input.tokenId, 'token id');
    requireValue(input.tokenSecret, 'token secret');
    requireValue(input.httpMethod, 'HTTP method');
    requireValue(input.url, 'URL');

    String nonce = String.isBlank(input.nonce) ? generateNonce() : input.nonce;
    String timestamp = String.isBlank(input.timestamp)
      ? String.valueOf(Datetime.now().getTime() / 1000)
      : input.timestamp;
    Map<String, String> oauthParams = new Map<String, String>{
      'oauth_consumer_key' => input.consumerKey,
      'oauth_token' => input.tokenId,
      'oauth_signature_method' => 'HMAC-SHA256',
      'oauth_timestamp' => timestamp,
      'oauth_nonce' => nonce,
      'oauth_version' => '1.0'
    };
    Map<String, String> signatureParams = new Map<String, String>();
    signatureParams.putAll(oauthParams);
    if (input.queryParams != null) {
      signatureParams.putAll(input.queryParams);
    }
    String signature = sign(
      input.httpMethod,
      input.url,
      signatureParams,
      input.consumerSecret,
      input.tokenSecret
    );
    oauthParams.put('oauth_signature', signature);

    List<String> headerParts = new List<String>{'OAuth realm="' + encode(input.realm) + '"'};
    for (String key : sortedKeys(oauthParams)) {
      headerParts.add(encode(key) + '="' + encode(oauthParams.get(key)) + '"');
    }
    return String.join(headerParts, ', ');
  }

  public static String sign(
    String httpMethod,
    String url,
    Map<String, String> params,
    String consumerSecret,
    String tokenSecret
  ) {
    List<String> encodedPairs = new List<String>();
    for (String key : sortedKeys(params)) {
      encodedPairs.add(encode(key) + '=' + encode(params.get(key)));
    }
    String baseString = httpMethod.toUpperCase() + '&' + encode(url) + '&' + encode(String.join(encodedPairs, '&'));
    String signingKey = encode(consumerSecret) + '&' + encode(tokenSecret);
    Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(baseString), Blob.valueOf(signingKey));
    return EncodingUtil.base64Encode(mac);
  }

  private static List<String> sortedKeys(Map<String, String> params) {
    List<String> keys = params == null ? new List<String>() : new List<String>(params.keySet());
    keys.sort();
    return keys;
  }

  private static String encode(String value) {
    return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8')
      .replace('+', '%20')
      .replace('*', '%2A')
      .replace('%7E', '~');
  }

  private static String generateNonce() {
    return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(Math.random())))).substring(0, 16);
  }

  private static void requireValue(String value, String label) {
    if (String.isBlank(value)) {
      throw new NetSuiteRequestSignerException('NetSuite ' + label + ' is required for token-based authentication signing.');
    }
  }

  public class NetSuiteRequestSignerException extends Exception {}
}