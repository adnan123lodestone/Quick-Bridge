public with sharing class QuickBooksBulkQueryService {
    private static final Integer ID_QUERY_CHUNK_SIZE = 100;
    private static final Integer QUERY_PAGE_SIZE = 1000;
    private static final Set<String> SUPPORTED_ENTITY_NAMES = new Set<String>{ 'Customer', 'Vendor', 'Item', 'Invoice', 'CreditMemo', 'PurchaseOrder' };

    public class UnsupportedQuickBooksEntityException extends Exception {}

    public static List<Map<String, Object>> queryUpdatedSince(String entityName, String lastSyncDate) {
        String normalizedEntityName = normalizeEntityName(entityName);
        String query = 'select * from ' + normalizedEntityName;
        if (String.isNotBlank(lastSyncDate)) {
            query += ' Where Metadata.LastUpdatedTime > \'' + escapeQueryLiteral(lastSyncDate) + '\'';
        }
        return executeEntityQuery(normalizedEntityName, query);
    }

    public static List<Map<String, Object>> queryByIds(String entityName, Set<String> ids) {
        String normalizedEntityName = normalizeEntityName(entityName);
        if (ids == null || ids.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<String> idValues = new List<String>();
        for (String idValue : ids) {
            if (String.isNotBlank(idValue)) {
                idValues.add(idValue.trim());
            }
        }
        if (idValues.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> records = new List<Map<String, Object>>();
        for (Integer startIndex = 0; startIndex < idValues.size(); startIndex += ID_QUERY_CHUNK_SIZE) {
            List<String> literals = new List<String>();
            Integer endIndex = Math.min(startIndex + ID_QUERY_CHUNK_SIZE, idValues.size());
            for (Integer index = startIndex; index < endIndex; index++) {
                literals.add('\'' + escapeQueryLiteral(idValues[index]) + '\'');
            }
            String query = 'select * from ' + normalizedEntityName + ' Where Id in (' + String.join(literals, ',') + ')';
            records.addAll(executeEntityQuery(normalizedEntityName, query));
        }
        return records;
    }

    public static Map<String, Map<String, Object>> queryByIdsMap(String entityName, Set<String> ids) {
        Map<String, Map<String, Object>> recordsById = new Map<String, Map<String, Object>>();
        for (Map<String, Object> record : queryByIds(entityName, ids)) {
            if (record == null || !record.containsKey('Id') || record.get('Id') == null) {
                continue;
            }
            recordsById.put(String.valueOf(record.get('Id')), record);
        }
        return recordsById;
    }

    public static List<String> serializeRecords(List<Map<String, Object>> records) {
        List<String> payloads = new List<String>();
        if (records == null) {
            return payloads;
        }
        for (Map<String, Object> record : records) {
            if (record != null && record.containsKey('Id')) {
                payloads.add(JSON.serialize(record));
            }
        }
        return payloads;
    }

    private static List<Map<String, Object>> executeEntityQuery(String entityName, String query) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        Integer startPosition = 1;
        while (true) {
            List<Map<String, Object>> pageRecords = executeEntityQueryPage(
                entityName,
                query + ' STARTPOSITION ' + startPosition + ' MAXRESULTS ' + QUERY_PAGE_SIZE
            );
            records.addAll(pageRecords);
            if (pageRecords.size() < QUERY_PAGE_SIZE) {
                break;
            }
            startPosition += QUERY_PAGE_SIZE;
        }
        return records;
    }

    private static List<Map<String, Object>> executeEntityQueryPage(String entityName, String query) {
        String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
        HttpResponse response = QuickBooksAuthHandler.makeApiCall('GET', '/query?query=' + encodedQuery, null);
        if (response == null || response.getStatusCode() != 200 || String.isBlank(response.getBody())) {
            Integer statusCode = response == null ? null : response.getStatusCode();
            throw IntegrationRetryPolicy.exceptionForStatus(
                statusCode,
                'QuickBooks ' + entityName + ' query failed' +
                (statusCode == null ? '.' : ' with HTTP ' + statusCode + '.')
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        if (responseMap == null || !responseMap.containsKey('QueryResponse')) {
            return new List<Map<String, Object>>();
        }

        Map<String, Object> queryResponse = (Map<String, Object>) responseMap.get('QueryResponse');
        if (queryResponse == null || !queryResponse.containsKey(entityName)) {
            return new List<Map<String, Object>>();
        }

        List<Object> rows = (List<Object>) queryResponse.get(entityName);
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (rows == null) {
            return records;
        }
        for (Object row : rows) {
            if (row instanceof Map<String, Object>) {
                records.add((Map<String, Object>) row);
            }
        }
        return records;
    }

    private static String normalizeEntityName(String entityName) {
        if (String.isBlank(entityName)) {
            throw new UnsupportedQuickBooksEntityException('QuickBooks entity name is required.');
        }
        for (String supportedEntityName : SUPPORTED_ENTITY_NAMES) {
            if (supportedEntityName.equalsIgnoreCase(entityName.trim())) {
                return supportedEntityName;
            }
        }
        throw new UnsupportedQuickBooksEntityException('Unsupported QuickBooks entity for bulk query: ' + entityName);
    }

    private static String escapeQueryLiteral(String value) {
        return value == null ? '' : value.replace('\\', '\\\\').replace('\'', '\\\'');
    }
}
