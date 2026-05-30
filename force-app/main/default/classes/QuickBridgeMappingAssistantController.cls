public with sharing class QuickBridgeMappingAssistantController {
    private static final Decimal HIGH_CONFIDENCE = 80;
    private static final Decimal MEDIUM_CONFIDENCE = 55;
    private static final Integer MAX_SUGGESTIONS = 12;

    public class MappingAssistantSummary {
        @AuraEnabled public Integer healthScore { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer requiredFieldsTotal { get; set; }
        @AuraEnabled public Integer requiredFieldsMapped { get; set; }
        @AuraEnabled public Integer missingRequiredCount { get; set; }
        @AuraEnabled public Integer riskyMappingCount { get; set; }
        @AuraEnabled public List<MissingField> missingRequiredFields { get; set; }
        @AuraEnabled public List<MappingRisk> risks { get; set; }
        @AuraEnabled public List<MappingSuggestion> topSuggestions { get; set; }

        public MappingAssistantSummary() {
            healthScore = 0;
            status = 'Needs Context';
            requiredFieldsTotal = 0;
            requiredFieldsMapped = 0;
            missingRequiredCount = 0;
            riskyMappingCount = 0;
            missingRequiredFields = new List<MissingField>();
            risks = new List<MappingRisk>();
            topSuggestions = new List<MappingSuggestion>();
        }
    }

    public class MappingSuggestion {
        @AuraEnabled public String connectorKey { get; set; }
        @AuraEnabled public String salesforceObject { get; set; }
        @AuraEnabled public String externalObject { get; set; }
        @AuraEnabled public String salesforceField { get; set; }
        @AuraEnabled public String salesforceFieldLabel { get; set; }
        @AuraEnabled public String salesforceFieldType { get; set; }
        @AuraEnabled public String externalField { get; set; }
        @AuraEnabled public String externalFieldLabel { get; set; }
        @AuraEnabled public String externalFieldType { get; set; }
        @AuraEnabled public String syncDirection { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
        @AuraEnabled public String confidenceLabel { get; set; }
        @AuraEnabled public String reason { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public Boolean canApply { get; set; }
    }

    public class MappingRisk {
        @AuraEnabled public String severity { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String salesforceField { get; set; }
        @AuraEnabled public String externalField { get; set; }
        @AuraEnabled public String suggestedFix { get; set; }
    }

    public class MissingField {
        @AuraEnabled public String externalField { get; set; }
        @AuraEnabled public String externalFieldLabel { get; set; }
        @AuraEnabled public String externalFieldType { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public String suggestedSalesforceField { get; set; }
        @AuraEnabled public String reason { get; set; }
    }

    public class MappingReviewResult {
        @AuraEnabled public Integer healthScore { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public List<MappingRisk> risks { get; set; }
        @AuraEnabled public List<MissingField> missingRequiredFields { get; set; }
        @AuraEnabled public List<MappingSuggestion> suggestions { get; set; }

        public MappingReviewResult() {
            healthScore = 0;
            status = 'Needs Context';
            risks = new List<MappingRisk>();
            missingRequiredFields = new List<MissingField>();
            suggestions = new List<MappingSuggestion>();
        }
    }

    private class FieldInfo {
        String label;
        String value;
        String type;
        Boolean required;

        FieldInfo(String label, String value, String type, Boolean required) {
            this.label = label;
            this.value = value;
            this.type = normalizeType(type);
            this.required = required == true;
        }
    }

    private class MappingRow {
        String sfField;
        String externalField;
        String syncDirection;
    }

    @AuraEnabled(cacheable=true)
    public static MappingAssistantSummary getSummary(String connectorKey, String salesforceObject, String externalObject) {
        MappingAssistantSummary summary = new MappingAssistantSummary();
        if (!hasContext(connectorKey, salesforceObject, externalObject)) {
            return summary;
        }

        MappingReviewResult review = reviewMappings(
            connectorKey,
            salesforceObject,
            externalObject,
            JSON.serialize(loadExistingMappings(connectorKey, salesforceObject, externalObject))
        );
        summary.healthScore = review.healthScore;
        summary.status = review.status;
        summary.missingRequiredFields = review.missingRequiredFields;
        summary.risks = review.risks;
        summary.topSuggestions = review.suggestions;
        summary.missingRequiredCount = review.missingRequiredFields.size();
        summary.riskyMappingCount = review.risks.size();

        List<FieldInfo> externalFields = externalFieldsFor(connectorKey, salesforceObject, externalObject);
        Integer requiredTotal = 0;
        for (FieldInfo field : externalFields) {
            if (field.required) {
                requiredTotal++;
            }
        }
        summary.requiredFieldsTotal = requiredTotal;
        summary.requiredFieldsMapped = Math.max(0, requiredTotal - summary.missingRequiredCount);
        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<MappingSuggestion> suggestMappings(String connectorKey, String salesforceObject, String externalObject) {
        if (!hasContext(connectorKey, salesforceObject, externalObject) || !isSupportedConnector(connectorKey)) {
            return new List<MappingSuggestion>();
        }
        return buildSuggestions(
            normalizeConnector(connectorKey),
            salesforceObject,
            externalObject,
            loadExistingMappings(connectorKey, salesforceObject, externalObject)
        );
    }

    @AuraEnabled(cacheable=true)
    public static MappingReviewResult reviewMappings(String connectorKey, String salesforceObject, String externalObject, String mappingsJson) {
        MappingReviewResult result = new MappingReviewResult();
        if (!hasContext(connectorKey, salesforceObject, externalObject) || !isSupportedConnector(connectorKey)) {
            return result;
        }

        String normalizedConnector = normalizeConnector(connectorKey);
        List<MappingRow> mappings = parseMappings(mappingsJson);
        List<FieldInfo> sfFields = salesforceFieldsFor(salesforceObject);
        List<FieldInfo> externalFields = externalFieldsFor(normalizedConnector, salesforceObject, externalObject);
        Map<String, FieldInfo> sfByName = byValue(sfFields);
        Map<String, FieldInfo> externalByName = byValue(externalFields);

        Set<String> mappedExternal = new Set<String>();
        Set<String> seenExternal = new Set<String>();
        Set<String> seenSalesforce = new Set<String>();
        Boolean hasTypeRisk = false;
        Boolean hasDuplicateExternal = false;
        Boolean hasDuplicateSalesforce = false;

        for (MappingRow row : mappings) {
            if (String.isBlank(row.sfField) || String.isBlank(row.externalField)) {
                continue;
            }
            mappedExternal.add(row.externalField);
            if (seenExternal.contains(row.externalField)) {
                hasDuplicateExternal = true;
                result.risks.add(risk('High', 'Duplicate external field mapping.', row.sfField, row.externalField, 'Keep only one mapping for this external field.'));
            }
            seenExternal.add(row.externalField);

            if (seenSalesforce.contains(row.sfField) && isRiskyDirection(row.syncDirection)) {
                hasDuplicateSalesforce = true;
                result.risks.add(risk('Warning', 'The same Salesforce field is used by multiple sync mappings.', row.sfField, row.externalField, 'Confirm this field should feed multiple external fields.'));
            }
            seenSalesforce.add(row.sfField);

            FieldInfo sfField = sfByName.get(row.sfField);
            FieldInfo externalField = externalByName.get(row.externalField);
            if (sfField != null && externalField != null && !isTypeCompatible(sfField.type, externalField.type)) {
                hasTypeRisk = true;
                result.risks.add(risk('High', 'Incompatible field type mapping.', row.sfField, row.externalField, 'Choose a Salesforce field with a compatible type.'));
            }
        }

        for (FieldInfo externalField : externalFields) {
            if (externalField.required && !mappedExternal.contains(externalField.value)) {
                MissingField missing = new MissingField();
                missing.externalField = externalField.value;
                missing.externalFieldLabel = cleanExternalLabel(externalField.label);
                missing.externalFieldType = externalField.type;
                missing.required = true;
                MappingSuggestion suggestion = bestSuggestionFor(normalizedConnector, salesforceObject, externalObject, externalField, sfFields, mappings);
                if (suggestion != null) {
                    missing.suggestedSalesforceField = suggestion.salesforceField;
                    missing.reason = suggestion.reason;
                } else {
                    missing.reason = 'No compatible Salesforce field was found.';
                }
                result.missingRequiredFields.add(missing);
            }
        }

        result.suggestions = buildSuggestions(normalizedConnector, salesforceObject, externalObject, mappings);
        Integer score = 100;
        if (!result.missingRequiredFields.isEmpty()) {
            score -= 25;
        }
        if (hasTypeRisk) {
            score -= 15;
        }
        if (hasDuplicateExternal) {
            score -= 10;
        }
        if (hasDuplicateSalesforce) {
            score -= 10;
        }
        if (missingHighValueOptional(mappedExternal, externalFields)) {
            score -= 5;
        }
        result.healthScore = Math.max(0, Math.min(100, score));
        result.status = statusFor(result.healthScore);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static String explainSuggestion(String connectorKey, String salesforceObject, String externalObject, String salesforceField, String externalField) {
        if (!hasContext(connectorKey, salesforceObject, externalObject)) {
            return 'Select a Salesforce object and external object to analyze mappings.';
        }
        List<MappingSuggestion> suggestions = suggestMappings(connectorKey, salesforceObject, externalObject);
        for (MappingSuggestion suggestion : suggestions) {
            if (suggestion.salesforceField == salesforceField && suggestion.externalField == externalField) {
                return suggestion.reason;
            }
        }
        return 'This recommendation is based on normalized field names, synonyms, and compatible field types.';
    }

    @AuraEnabled(cacheable=true)
    public static String generateCodexPrompt(String connectorKey, String salesforceObject, String externalObject) {
        MappingReviewResult review = reviewMappings(connectorKey, salesforceObject, externalObject, null);
        List<String> lines = new List<String>();
        lines.add('Implement mapping fixes for QuickBridge.');
        lines.add('Connector: ' + safe(connectorKey));
        lines.add('Salesforce object: ' + safe(salesforceObject));
        lines.add('External object/action: ' + safe(externalObject));
        lines.add('');
        lines.add('Missing required fields:');
        if (review.missingRequiredFields.isEmpty()) {
            lines.add('- None detected');
        } else {
            for (MissingField missing : review.missingRequiredFields) {
                lines.add('- ' + missing.externalField + ' -> suggested Salesforce field: ' + safe(missing.suggestedSalesforceField));
            }
        }
        lines.add('Risks:');
        if (review.risks.isEmpty()) {
            lines.add('- None detected');
        } else {
            for (MappingRisk riskRow : review.risks) {
                lines.add('- ' + riskRow.severity + ': ' + riskRow.message + ' (' + safe(riskRow.salesforceField) + ' -> ' + safe(riskRow.externalField) + ')');
            }
        }
        lines.add('Suggested mappings:');
        for (MappingSuggestion suggestion : review.suggestions) {
            lines.add('- ' + suggestion.salesforceField + ' -> ' + suggestion.externalField + ' (' + suggestion.confidenceLabel + ', ' + suggestion.confidence + '%)');
        }
        lines.add('');
        lines.add('Constraints: preserve existing mapping save behavior; add tests; do not hard-code if metadata/service can support it; do not process secrets; do not remove existing components.');
        return String.join(lines, '\n');
    }

    private static List<MappingSuggestion> buildSuggestions(String connectorKey, String salesforceObject, String externalObject, List<MappingRow> existingMappings) {
        List<FieldInfo> sfFields = salesforceFieldsFor(salesforceObject);
        List<FieldInfo> externalFields = externalFieldsFor(connectorKey, salesforceObject, externalObject);
        List<MappingSuggestion> suggestions = new List<MappingSuggestion>();
        for (FieldInfo externalField : externalFields) {
            MappingSuggestion suggestion = bestSuggestionFor(connectorKey, salesforceObject, externalObject, externalField, sfFields, existingMappings);
            if (suggestion != null && suggestion.confidence >= MEDIUM_CONFIDENCE) {
                suggestions.add(suggestion);
            }
        }
        suggestions.sort(new SuggestionComparator());
        while (suggestions.size() > MAX_SUGGESTIONS) {
            suggestions.remove(suggestions.size() - 1);
        }
        return suggestions;
    }

    private static MappingSuggestion bestSuggestionFor(String connectorKey, String salesforceObject, String externalObject, FieldInfo externalField, List<FieldInfo> sfFields, List<MappingRow> existingMappings) {
        Set<String> mappedExternal = new Set<String>();
        Set<String> mappedPairs = new Set<String>();
        for (MappingRow row : existingMappings) {
            if (String.isNotBlank(row.externalField)) {
                mappedExternal.add(row.externalField);
            }
            if (String.isNotBlank(row.sfField) && String.isNotBlank(row.externalField)) {
                mappedPairs.add(row.sfField + '|' + row.externalField);
            }
        }

        MappingSuggestion best;
        for (FieldInfo sfField : sfFields) {
            if (!isTypeCompatible(sfField.type, externalField.type)) {
                continue;
            }
            Decimal confidence = score(sfField, externalField);
            if (externalField.required) {
                confidence += 5;
            }
            confidence = Math.min(99, confidence);
            if (confidence < MEDIUM_CONFIDENCE) {
                continue;
            }
            MappingSuggestion suggestion = new MappingSuggestion();
            suggestion.connectorKey = connectorKey;
            suggestion.salesforceObject = salesforceObject;
            suggestion.externalObject = externalObject;
            suggestion.salesforceField = sfField.value;
            suggestion.salesforceFieldLabel = sfField.label;
            suggestion.salesforceFieldType = sfField.type;
            suggestion.externalField = externalField.value;
            suggestion.externalFieldLabel = cleanExternalLabel(externalField.label);
            suggestion.externalFieldType = externalField.type;
            suggestion.syncDirection = defaultDirection(connectorKey);
            suggestion.confidence = confidence.setScale(0);
            suggestion.confidenceLabel = confidence >= HIGH_CONFIDENCE ? 'High' : 'Medium';
            suggestion.reason = reasonFor(sfField, externalField, confidence);
            suggestion.required = externalField.required;
            suggestion.canApply = !mappedExternal.contains(externalField.value) && !mappedPairs.contains(sfField.value + '|' + externalField.value);
            if (mappedExternal.contains(externalField.value)) {
                suggestion.confidence = Math.max(0, suggestion.confidence - 30);
                suggestion.reason += ' Existing mapping already uses this external field.';
            }
            if (best == null || suggestion.confidence > best.confidence) {
                best = suggestion;
            }
        }
        return best;
    }

    private static Decimal score(FieldInfo sfField, FieldInfo externalField) {
        String sfNorm = normalizeForCompare(sfField.value + ' ' + sfField.label);
        String extNorm = normalizeForCompare(externalField.value + ' ' + externalField.label);
        Set<String> sfTokens = tokens(sfField.value + ' ' + sfField.label);
        Set<String> extTokens = tokens(externalField.value + ' ' + externalField.label);
        Decimal scoreValue = 0;
        if (sfNorm == extNorm || normalizeForCompare(sfField.value) == normalizeForCompare(externalField.value)) {
            scoreValue = 92;
        } else if (!sfTokens.isEmpty() && sfTokens.equals(extTokens)) {
            scoreValue = 84;
        } else {
            Integer overlap = 0;
            for (String token : sfTokens) {
                if (extTokens.contains(token)) {
                    overlap++;
                }
            }
            if (overlap > 0) {
                scoreValue = 58 + (overlap * 8);
            }
            if (hasSynonymOverlap(sfTokens, extTokens)) {
                scoreValue = Math.max(scoreValue, 72);
            }
        }
        if (isTypeCompatible(sfField.type, externalField.type)) {
            scoreValue += 8;
        }
        return Math.min(99, scoreValue);
    }

    private static String reasonFor(FieldInfo sfField, FieldInfo externalField, Decimal confidence) {
        if (confidence >= HIGH_CONFIDENCE) {
            return 'High-confidence match from field name, label, and compatible types.';
        }
        return 'Suggested from normalized tokens, synonyms, and compatible types.';
    }

    private static List<FieldInfo> salesforceFieldsFor(String salesforceObject) {
        List<FieldInfo> fields = new List<FieldInfo>();
        if (String.isBlank(salesforceObject)) {
            return fields;
        }
        try {
            for (Map<String, String> row : FieldMappingController.getObjectFields(salesforceObject)) {
                fields.add(new FieldInfo(row.get('label'), row.get('value'), row.get('type'), false));
            }
        } catch (Exception ignored) {
        }
        return fields;
    }

    private static List<FieldInfo> externalFieldsFor(String connectorKey, String salesforceObject, String externalObject) {
        List<FieldInfo> fields = new List<FieldInfo>();
        String connector = normalizeConnector(connectorKey);
        try {
            if (connector == 'qbonline' || connector == 'qbo') {
                for (Map<String, Object> row : FieldMappingController.getQuickBooksFields(salesforceObject, externalObject)) {
                    fields.add(fromExternalMap(row));
                }
            } else if (connector == 'shopify') {
                for (Map<String, Object> row : FieldMappingController.getShopifyFields(salesforceObject, externalObject)) {
                    fields.add(fromExternalMap(row));
                }
            } else if (connector == 'fedex') {
                for (Map<String, Object> row : FieldMappingController.getFedExFields(externalObject, null)) {
                    fields.add(fromExternalMap(row));
                }
            } else if (connector == 'ups') {
                for (Map<String, Object> row : FieldMappingController.getUPSFields(externalObject, null)) {
                    fields.add(fromExternalMap(row));
                }
            } else if (isPaymentConnector(connector)) {
                fields.addAll(paymentFields(connector));
            }
        } catch (Exception ignored) {
        }
        return fields;
    }

    private static FieldInfo fromExternalMap(Map<String, Object> row) {
        return new FieldInfo(
            String.valueOf(row.get('label')),
            String.valueOf(row.get('value')),
            String.valueOf(row.get('type')),
            Boolean.valueOf(String.valueOf(row.get('required')))
        );
    }

    private static List<FieldInfo> paymentFields(String connectorKey) {
        List<FieldInfo> fields = new List<FieldInfo>();
        fields.add(new FieldInfo('Amount', 'amount', 'NUMBER', true));
        fields.add(new FieldInfo('Reference Number', 'referenceNumber', 'STRING', true));
        fields.add(new FieldInfo('Status', 'status', 'STRING', true));
        fields.add(new FieldInfo('Invoice Date', 'invoiceDate', 'DATE', true));
        fields.add(new FieldInfo('Customer Email', 'customerEmail', 'STRING', false));
        fields.add(new FieldInfo('Gateway Transaction Id', 'gatewayTransactionId', 'STRING', true));
        if (connectorKey == 'stripe') {
            fields.add(new FieldInfo('Stripe Invoice Id', 'stripeInvoiceId', 'STRING', true));
            fields.add(new FieldInfo('Stripe Hosted Invoice URL', 'hostedInvoiceUrl', 'STRING', true));
        } else if (connectorKey == 'paypal') {
            fields.add(new FieldInfo('PayPal Order Id', 'paypalOrderId', 'STRING', false));
        } else if (connectorKey == 'authorizenet') {
            fields.add(new FieldInfo('Auth Code', 'authCode', 'STRING', false));
        }
        return fields;
    }

    private static List<MappingRow> loadExistingMappings(String connectorKey, String salesforceObject, String externalObject) {
        List<MappingRow> rows = new List<MappingRow>();
        String connector = normalizeConnector(connectorKey);
        try {
            List<Map<String, String>> existing;
            if (connector == 'fedex') {
                existing = FieldMappingController.getExistingFedExMappings(externalObject, salesforceObject);
            } else if (connector == 'ups') {
                existing = FieldMappingController.getExistingUPSMappings(externalObject, salesforceObject);
            } else if (connector == 'shopify') {
                existing = FieldMappingController.getExistingMappings('shopify', salesforceObject);
            } else if (connector == 'qbo' || connector == 'qbonline') {
                existing = FieldMappingController.getExistingMappings('qbonline', salesforceObject);
            } else {
                existing = new List<Map<String, String>>();
            }
            for (Map<String, String> row : existing) {
                MappingRow mapping = new MappingRow();
                mapping.sfField = row.get('sfField');
                mapping.externalField = row.get('externalField');
                mapping.syncDirection = row.get('syncDirection');
                rows.add(mapping);
            }
        } catch (Exception ignored) {
        }
        return rows;
    }

    private static List<MappingRow> parseMappings(String mappingsJson) {
        List<MappingRow> rows = new List<MappingRow>();
        if (String.isBlank(mappingsJson)) {
            return rows;
        }
        try {
            List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(mappingsJson);
            for (Object rawRow : rawRows) {
                Map<String, Object> raw = (Map<String, Object>) rawRow;
                MappingRow row = new MappingRow();
                row.sfField = firstString(raw, new List<String>{ 'sfField', 'salesforceField', 'sourceField' });
                row.externalField = firstString(raw, new List<String>{ 'externalField', 'targetField', 'qbField' });
                row.syncDirection = String.valueOf(raw.get('syncDirection'));
                rows.add(row);
            }
        } catch (Exception ignored) {
        }
        return rows;
    }

    private static String firstString(Map<String, Object> raw, List<String> keys) {
        for (String key : keys) {
            if (raw.containsKey(key) && raw.get(key) != null && String.isNotBlank(String.valueOf(raw.get(key)))) {
                return String.valueOf(raw.get(key));
            }
        }
        return null;
    }

    private static Map<String, FieldInfo> byValue(List<FieldInfo> fields) {
        Map<String, FieldInfo> byName = new Map<String, FieldInfo>();
        for (FieldInfo field : fields) {
            byName.put(field.value, field);
        }
        return byName;
    }

    private static MappingRisk risk(String severity, String message, String sfField, String externalField, String suggestedFix) {
        MappingRisk riskRow = new MappingRisk();
        riskRow.severity = severity;
        riskRow.message = message;
        riskRow.salesforceField = sfField;
        riskRow.externalField = externalField;
        riskRow.suggestedFix = suggestedFix;
        return riskRow;
    }

    private static Boolean hasContext(String connectorKey, String salesforceObject, String externalObject) {
        return String.isNotBlank(connectorKey) && String.isNotBlank(salesforceObject) && String.isNotBlank(externalObject);
    }

    private static Boolean isSupportedConnector(String connectorKey) {
        String connector = normalizeConnector(connectorKey);
        return connector == 'qbo' || connector == 'qbonline' || connector == 'shopify' || connector == 'fedex' || connector == 'ups' || isPaymentConnector(connector);
    }

    private static Boolean isPaymentConnector(String connectorKey) {
        return connectorKey == 'stripe' || connectorKey == 'paypal' || connectorKey == 'authorizenet';
    }

    private static String normalizeConnector(String connectorKey) {
        return String.isBlank(connectorKey) ? '' : connectorKey.trim().toLowerCase();
    }

    private static String defaultDirection(String connectorKey) {
        if (connectorKey == 'fedex') {
            return 'SF to FedEx';
        }
        if (connectorKey == 'ups') {
            return 'SF to UPS';
        }
        if (connectorKey == 'shopify') {
            return 'Two-Way';
        }
        return 'Two-Way';
    }

    private static Boolean isRiskyDirection(String directionValue) {
        return String.isBlank(directionValue) || directionValue.contains('Two') || directionValue.contains('SF to') || directionValue.contains('Carrier');
    }

    private static String statusFor(Integer score) {
        if (score >= 90) {
            return 'Healthy';
        }
        if (score >= 70) {
            return 'Good';
        }
        if (score >= 50) {
            return 'Needs Attention';
        }
        return 'High Risk';
    }

    private static Boolean missingHighValueOptional(Set<String> mappedExternal, List<FieldInfo> externalFields) {
        for (FieldInfo field : externalFields) {
            if (!field.required && !mappedExternal.contains(field.value)) {
                Set<String> fieldTokens = tokens(field.value + ' ' + field.label);
                if (fieldTokens.contains('email') || fieldTokens.contains('phone') || fieldTokens.contains('amount') || fieldTokens.contains('status')) {
                    return true;
                }
            }
        }
        return false;
    }

    private static String cleanExternalLabel(String labelValue) {
        String value = safe(labelValue);
        Integer indexValue = value.indexOf(' - ');
        return indexValue >= 0 ? value.substring(indexValue + 3) : value;
    }

    private static String normalizeForCompare(String value) {
        return String.join(new List<String>(tokens(value)), '');
    }

    private static Set<String> tokens(String value) {
        Set<String> result = new Set<String>();
        if (String.isBlank(value)) {
            return result;
        }
        String expanded = value.replaceAll('([a-z])([A-Z])', '$1 $2')
            .replaceAll('[^A-Za-z0-9]+', ' ')
            .toLowerCase();
        for (String part : expanded.split('\\s+')) {
            if (String.isNotBlank(part) && part != 'qb' && part != 'sf' && part != 'fedex' && part != 'ups' && part != 'shopify') {
                result.add(part);
            }
        }
        return expandSynonyms(result);
    }

    private static Set<String> expandSynonyms(Set<String> source) {
        Set<String> result = new Set<String>();
        result.addAll(source);
        for (Set<String> groupValues : synonymGroups()) {
            Boolean hit = false;
            for (String token : source) {
                if (groupValues.contains(token)) {
                    hit = true;
                    break;
                }
            }
            if (hit) {
                result.addAll(groupValues);
            }
        }
        return result;
    }

    private static Boolean hasSynonymOverlap(Set<String> leftValues, Set<String> rightValues) {
        for (String token : leftValues) {
            if (rightValues.contains(token)) {
                return true;
            }
        }
        return false;
    }

    private static List<Set<String>> synonymGroups() {
        return new List<Set<String>>{
            new Set<String>{ 'postal', 'zipcode', 'zip', 'code', 'shippingpostalcode' },
            new Set<String>{ 'country', 'countrycode', 'shippingcountry' },
            new Set<String>{ 'state', 'province', 'region', 'shippingstate' },
            new Set<String>{ 'sku', 'stockkeepingunit', 'productcode', 'product', 'id' },
            new Set<String>{ 'email', 'customeremail', 'billtoemail', 'personemail' },
            new Set<String>{ 'phone', 'mobile', 'customerphone' },
            new Set<String>{ 'amount', 'total', 'grandtotal', 'balance', 'totalamt' },
            new Set<String>{ 'name', 'displayname', 'fullname', 'title' },
            new Set<String>{ 'city', 'town', 'shippingcity' },
            new Set<String>{ 'street', 'address', 'addressline1', 'shippingstreet' },
            new Set<String>{ 'weight', 'packageweight' },
            new Set<String>{ 'currency', 'currencycode' },
            new Set<String>{ 'quantity', 'qty' },
            new Set<String>{ 'tax', 'taxamount' },
            new Set<String>{ 'discount', 'discountamount' },
            new Set<String>{ 'status', 'state' },
            new Set<String>{ 'date', 'time', 'txn' }
        };
    }

    private static String normalizeType(String typeValue) {
        String value = String.isBlank(typeValue) ? 'STRING' : typeValue.trim().toUpperCase();
        if (value == 'TEXT' || value == 'PICKLIST' || value == 'EMAIL' || value == 'PHONE' || value == 'URL' || value == 'REFERENCE' || value == 'ID') {
            return 'STRING';
        }
        if (value == 'CURRENCY' || value == 'DOUBLE' || value == 'DECIMAL' || value == 'PERCENT' || value == 'INTEGER' || value == 'LONG' || value == 'NUMBER') {
            return 'NUMBER';
        }
        if (value == 'DATETIME') {
            return 'DATETIME';
        }
        if (value == 'DATE') {
            return 'DATE';
        }
        if (value == 'BOOLEAN') {
            return 'BOOLEAN';
        }
        return 'STRING';
    }

    private static Boolean isTypeCompatible(String sfType, String externalType) {
        String sfValue = normalizeType(sfType);
        String externalValue = normalizeType(externalType);
        if (sfValue == externalValue) {
            return true;
        }
        if (sfValue == 'DATETIME' && externalValue == 'STRING') {
            return true;
        }
        if (sfValue == 'DATE' && externalValue == 'DATETIME') {
            return true;
        }
        return false;
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    private class SuggestionComparator implements System.Comparator<MappingSuggestion> {
        public Integer compare(MappingSuggestion leftValue, MappingSuggestion rightValue) {
            if (leftValue.confidence == rightValue.confidence) {
                return leftValue.externalField.compareTo(rightValue.externalField);
            }
            return leftValue.confidence > rightValue.confidence ? -1 : 1;
        }
    }
}
