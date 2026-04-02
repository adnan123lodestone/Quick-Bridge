/**
 * -----------------------------------------------------------------------------
 * Class Name     : WishlistEventService
 * Endpoint URL   : /services/apexrest/wishlistevent
 * Purpose        : Public RESTful API to capture customer wishlist event data
 *                  and store it in Salesforce using the Wishlist_Event__c object.
 *
 * Access Level   : Exposed via a Salesforce Force.com Site (unauthenticated),
 *                  but protected using a static API token passed in a custom header.
 *
 * Authentication : Requires a valid API token to be passed in the request header:
 *                  Header: X-Access-Token: <your_token_here>
 *                  The token is validated against Integration__mdt (MasterLabel = 'Swym').
 *
 * Request Method : HTTP POST
 * Expected Payload:
 * {
 *   "customer_ids": {
 *     "email_id": "test@example.com"
 *   },
 *   "properties": {
 *     "product_id": "123",
 *     "variant_id": "456",
 *     "variant_info": "Large / Red",
 *     "product_name": "T-Shirt",
 *     "product_price": 29.99,
 *     "product_quantity": 1,
 *     "product_url": "https://example.com/product",
 *     "image_url": "https://example.com/image.png",
 *     "variant_sku": "TSHIRT-RED-L"
 *   },
 *   "timestamp": "2025-05-28T10:00:00Z",
 *   "event_type": "add_to_wishlist"
 * }
 *
 * Response Format: JSON
 * {
 *   "statusCode": 200,
 *   "message": "Wishlist Event created successfully.",
 *   "success": true
 * }
 *
 * Notes:
 * - Make sure the Site Guest User Profile has access to the Apex class, 
 *   object `Wishlist_Event__c`, and necessary fields.
 * - Custom Metadata must contain the valid token in Integration__mdt.Access_Token__c
 * - Timestamp is expected in ISO 8601 format (e.g., 2025-05-28T10:00:00Z).
 * -----------------------------------------------------------------------------
 */

@RestResource(urlMapping='/wishlistevent')
global with sharing class WishlistEventService {

    global class WishlistEventRequest {
        public CustomerIds customer_ids;
        public Properties properties;
        public String timestamp;
        public String event_type;
    }

    global class CustomerIds {
        public String email_id;
    }

    global class Properties {
        public String product_id;
        public String variant_id;
        public String variant_info;
        public String product_name;
        public Decimal product_price;
        public Integer product_quantity;
        public String product_url;
        public String image_url;
        public String variant_sku;
    }

    global class ApiResponse {
        public Integer statusCode;
        public String message;
        public Boolean success;

        public ApiResponse(Integer statusCode, String message, Boolean success) {
            this.statusCode = statusCode;
            this.message = message;
            this.success = success;
        }
    }

    @HttpPost
    global static void createEvent() {
        RestResponse res = RestContext.response;
        ApiResponse response;

        try {
            RestRequest req = RestContext.request;

            String accessTokenHeader = req.headers.get('X-Access-Token');
            if (String.isBlank(accessTokenHeader)) {
                response = new ApiResponse(401, 'Missing or malformed X-Access-Token header.', false);
                returnError(res, response);
                return;
            }

            String accessToken = accessTokenHeader.trim();

            String expectedToken = null;
            List<Integration__mdt> tokens = [
                SELECT Access_Token__c FROM Integration__mdt WHERE MasterLabel = 'Swym' LIMIT 1
            ];
            if (!tokens.isEmpty()) {
                expectedToken = tokens[0].Access_Token__c;
            }

            if (String.isBlank(expectedToken) || accessToken != expectedToken) {
                response = new ApiResponse(401, 'Invalid or unauthorized token.', false);
                returnError(res, response);
                return;
            }

            String reqBody = req.requestBody.toString();
            WishlistEventRequest eventReq;
            try {
                eventReq = (WishlistEventRequest) JSON.deserialize(reqBody, WishlistEventRequest.class);
            } catch (Exception ex) {
                response = new ApiResponse(400, 'Invalid request payload.', false);
                returnError(res, response);
                return;
            }

            if (String.isBlank(eventReq.customer_ids?.email_id) ||
                String.isBlank(eventReq.properties?.variant_sku)) {
                response = new ApiResponse(400, 'Missing required fields: email_id or variant_sku.', false);
                returnError(res, response);
                return;
            }

            Account matchedAccount;
            List<Account> accounts = [
                SELECT Id FROM Account WHERE PersonEmail = :eventReq.customer_ids.email_id WITH SYSTEM_MODE LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                matchedAccount = accounts[0];
            }

            Product2 matchedProduct;
            List<Product2> products = [
                SELECT Id FROM Product2 WHERE StockKeepingUnit = :eventReq.properties.variant_sku WITH SYSTEM_MODE LIMIT 1
            ];
            if (!products.isEmpty()) {
                matchedProduct = products[0];
            }

            Wishlist_Event__c event = new Wishlist_Event__c();
            event.Customer_Email__c = eventReq.customer_ids.email_id;
            event.Product_ID__c = eventReq.properties.product_id;
            event.Variant_ID__c = eventReq.properties.variant_id;
            event.Variant_Info__c = eventReq.properties.variant_info;
            event.Product_Name__c = eventReq.properties.product_name;
            event.Product_Price__c = eventReq.properties.product_price;
            event.Product_Quantity__c = eventReq.properties.product_quantity;
            event.Product_URL__c = eventReq.properties.product_url;
            event.Image_URL__c = eventReq.properties.image_url;
            event.Variant_SKU__c = eventReq.properties.variant_sku;
            event.Event_Timestamp__c = convertTimestamp(eventReq.timestamp);
            event.Event_Type__c = eventReq.event_type;

            if (matchedAccount != null) {
                event.Account__c = matchedAccount.Id;
            }
            if (matchedProduct != null) {
                event.Product__c = matchedProduct.Id;
            }

            insert event;

            response = new ApiResponse(200, 'Wishlist Event created successfully.', true);
            res.statusCode = response.statusCode;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception ex) {
            System.debug('Error: ' + ex.getMessage());
            response = new ApiResponse(400, 'Error: ' + ex.getMessage(), false);
            returnError(res, response);
        }
    }

    public static DateTime convertTimestamp(String iso8601_ts) {
        JSONParser parser = JSON.createParser('{"t":"' + iso8601_ts + '"}');
        parser.nextToken();    // Start object
        parser.nextValue();    // Move to value
        return DateTime.newInstance(parser.getDateTimeValue().getTime());
    }

    private static void returnError(RestResponse res, ApiResponse response) {
        res.statusCode = response.statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }
}