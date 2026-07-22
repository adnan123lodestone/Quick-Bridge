@isTest
private class QuickBooksBulkQueryServiceTest {
    private static Integer queryCalls = 0;
    private static String mockMode = 'chunk';

    private class BulkQueryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            queryCalls++;
            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            System.assert(endpoint.contains('/query?query='), 'Bulk query service must use the QuickBooks query endpoint.');

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            if (mockMode == 'paginate' && endpoint.contains('startposition+1+')) {
                response.setBody(buildQueryResponse('Customer', 1000));
            } else if (mockMode == 'paginate' && endpoint.contains('startposition+1001+')) {
                response.setBody(buildQueryResponse('Customer', 1));
            } else {
                response.setBody(buildQueryResponse('Invoice', 1));
            }
            return response;
        }
    }

    @isTest
    static void queryByIdsChunksLargeIdLists() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        queryCalls = 0;
        mockMode = 'chunk';
        Test.setMock(HttpCalloutMock.class, new BulkQueryMock());

        Set<String> ids = new Set<String>();
        for (Integer index = 0; index < 101; index++) {
            ids.add('INV-' + index);
        }

        List<Map<String, Object>> records = QuickBooksBulkQueryService.queryByIds('Invoice', ids);

        System.assertEquals(2, queryCalls, '101 ids should be split into two QBO query calls.');
        System.assertEquals(2, records.size(), 'Each chunk response should be aggregated.');
    }

    @isTest
    static void queryByIdsMapIndexesRecordsByQuickBooksId() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        queryCalls = 0;
        mockMode = 'chunk';
        Test.setMock(HttpCalloutMock.class, new BulkQueryMock());

        Map<String, Map<String, Object>> recordsById = QuickBooksBulkQueryService.queryByIdsMap(
            'Invoice',
            new Set<String>{ 'INV-123' }
        );

        System.assertEquals(1, queryCalls, 'A single id set should use one QBO query call.');
        System.assertEquals(true, recordsById.containsKey('INV-0'), 'Returned QBO records should be indexed by Id.');
    }

    @isTest
    static void queryUpdatedSincePaginatesUntilShortPage() {
        QuickBooksAuthHandler.configureConnectionForTest('12345', 'QuickBooks_Test', '65');
        queryCalls = 0;
        mockMode = 'paginate';
        Test.setMock(HttpCalloutMock.class, new BulkQueryMock());

        List<Map<String, Object>> records = QuickBooksBulkQueryService.queryUpdatedSince('Customer', '2026-05-24');

        System.assertEquals(2, queryCalls, 'A full page must request the next QBO query page.');
        System.assertEquals(1001, records.size(), 'Paged results should be aggregated.');
    }

    @isTest
    static void unsupportedEntityIsRejectedBeforeCallout() {
        Boolean rejected = false;
        try {
            QuickBooksBulkQueryService.queryUpdatedSince('Payment', '2026-05-24');
        } catch (Exception e) {
            rejected = true;
            System.assert(e.getMessage().contains('Unsupported QuickBooks entity'));
        }
        System.assertEquals(true, rejected, 'Only known QBO sync entities should be accepted.');
    }

    private static String buildQueryResponse(String entityName, Integer countRows) {
        List<String> rows = new List<String>();
        for (Integer index = 0; index < countRows; index++) {
            rows.add('{"Id":"' + entityName.left(3).toUpperCase() + '-' + index + '"}');
        }
        return '{"QueryResponse":{"' + entityName + '":[' + String.join(rows, ',') + ']}}';
    }
}
