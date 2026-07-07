@IsTest
private class QuickBridgeMappingAssistantTest {
  @IsTest
  static void unknownConnectorReturnsEmptyResult() {
    Test.startTest();
    QuickBridgeMappingAssistantController.MappingAssistantSummary summary = QuickBridgeMappingAssistantController.getSummary(
      'not-a-connector',
      'Account',
      'Customer'
    );
    Test.stopTest();

    Assert.areEqual(0, summary.healthScore);
    Assert.areEqual('Needs Context', summary.status);
    Assert.areEqual(0, summary.topSuggestions.size());
    Assert.areEqual(0, summary.missingRequiredFields.size());
  }

  @IsTest
  static void suggestMappingsReturnsExactAndSynonymMatches() {
    Test.startTest();
    List<QuickBridgeMappingAssistantController.MappingSuggestion> suggestions = QuickBridgeMappingAssistantController.suggestMappings(
      'shopify',
      'Product2',
      'Product'
    );
    Test.stopTest();

    QuickBridgeMappingAssistantController.MappingSuggestion titleSuggestion;
    QuickBridgeMappingAssistantController.MappingSuggestion identifierSuggestion;
    for (
      QuickBridgeMappingAssistantController.MappingSuggestion suggestion : suggestions
    ) {
      if (suggestion.externalField == 'title') {
        titleSuggestion = suggestion;
      }
      if (suggestion.externalField == 'id') {
        identifierSuggestion = suggestion;
      }
    }

    Assert.isNotNull(
      titleSuggestion,
      'Expected a suggestion for Shopify title.'
    );
    Assert.isTrue(
      titleSuggestion.confidence >= 70,
      'Exact/label matches should be high confidence.'
    );
    Assert.areEqual(true, titleSuggestion.canApply);
    Assert.isNotNull(
      identifierSuggestion,
      'Expected at least one product identifier synonym suggestion.'
    );
  }

  @IsTest
  static void reviewMappingsDetectsMissingRequiredAndDuplicateFields() {
    String mappingsJson = JSON.serialize(
      new List<Map<String, Object>>{
        new Map<String, Object>{
          'sfField' => 'Name',
          'externalField' => 'CompanyName',
          'syncDirection' => 'Two-Way'
        },
        new Map<String, Object>{
          'sfField' => 'Name',
          'externalField' => 'CompanyName',
          'syncDirection' => 'Two-Way'
        }
      }
    );

    Test.startTest();
    QuickBridgeMappingAssistantController.MappingReviewResult result = QuickBridgeMappingAssistantController.reviewMappings(
      'qbonline',
      'Account',
      'Customer',
      mappingsJson
    );
    Test.stopTest();

    Assert.isTrue(result.healthScore < 100);
    Assert.isTrue(
      result.missingRequiredFields.size() > 0,
      'DisplayName should be reported missing.'
    );
    Assert.isTrue(
      result.risks.size() > 0,
      'Duplicate mappings should produce risks.'
    );
  }

    @IsTest
  static void reviewMappingsDetectsIncompatibleTypeRisk() {
    // Map a Number field (AnnualRevenue) to a Date field (TxnDate) – types are incompatible.
    String mappingsJson = JSON.serialize(
      new List<Map<String, Object>>{
        new Map<String, Object>{
          'sfField' => 'AnnualRevenue',
          'externalField' => 'TxnDate',
          'syncDirection' => 'SF to QBO'
        }
      }
    );

    Test.startTest();
    QuickBridgeMappingAssistantController.MappingReviewResult result = QuickBridgeMappingAssistantController.reviewMappings(
      'qbonline',
      'Account',
      'Invoice',
      mappingsJson
    );
    Test.stopTest();

    Boolean foundTypeRisk = false;
    for (
      QuickBridgeMappingAssistantController.MappingRisk risk : result.risks
    ) {
      if (risk.message != null && risk.message.contains('type')) {
        foundTypeRisk = true;
        break;
      }
    }
    System.assertEquals(true, foundTypeRisk, 'Type incompatibility risk should be detected for AnnualRevenue → TxnDate.');
  }

  @IsTest
  static void generateCodexPromptIncludesSelectedContextAndConstraints() {
    Test.startTest();
    String prompt = QuickBridgeMappingAssistantController.generateCodexPrompt(
      'fedex',
      'Case',
      'validateAddress'
    );
    Test.stopTest();

    Assert.isTrue(prompt.contains('fedex'));
    Assert.isTrue(prompt.contains('Case'));
    Assert.isTrue(prompt.contains('validateAddress'));
    Assert.isTrue(prompt.contains('preserve existing mapping save behavior'));
    Assert.isTrue(prompt.contains('do not process secrets'));
  }

  @IsTest
  static void metaMappingAssistantSuggestsCampaignAndLeadFields() {
    Test.startTest();
    List<QuickBridgeMappingAssistantController.MappingSuggestion> campaignSuggestions =
      QuickBridgeMappingAssistantController.suggestMappings(
        'meta',
        'Campaign',
        'Campaign'
      );
    QuickBridgeMappingAssistantController.MappingReviewResult leadReview =
      QuickBridgeMappingAssistantController.reviewMappings(
        'meta',
        'Lead',
        'LeadAd',
        null
      );
    Test.stopTest();

    Assert.isTrue(
      hasExternalSuggestion(campaignSuggestions, 'id'),
      'Campaign mapping guidance should expose the required Meta campaign id field.'
    );
    Assert.isTrue(
      leadReview.missingRequiredFields.size() > 0,
      'Lead ad mapping guidance should expose required Meta lead fields.'
    );
  }

  @IsTest
  static void reviewMappingsStaysWithinCpuBudgetForLargeObject() {
    // Account/Order resolve to large field sets; this is the path that previously
    // exceeded the Apex CPU limit because tokens were recomputed for every
    // (external x salesforce) field pair. Memoization should keep it well under
    // budget while still returning suggestions.
    Test.startTest();
    Long start = Limits.getCpuTime();
    QuickBridgeMappingAssistantController.MappingReviewResult result = QuickBridgeMappingAssistantController.reviewMappings(
      'qbonline',
      'Account',
      'Customer',
      null
    );
    Long elapsed = Limits.getCpuTime() - start;
    Test.stopTest();

    Assert.isNotNull(result, 'A review result should be returned.');
    Assert.isTrue(
      result.suggestions.size() > 0,
      'Suggestions should still be produced after the performance refactor.'
    );
    // Generous ceiling: the unoptimized path used ~13-15s; the optimized path runs
    // in well under 4s. This guards against a regression that reintroduces the
    // per-pair token recomputation.
    Assert.isTrue(
      elapsed < 4000,
      'Suggestion scoring should stay well within the CPU budget; took ' +
      elapsed +
      'ms.'
    );
  }

  @IsTest
  static void blankParametersAreHandledSafely() {
    Test.startTest();
    QuickBridgeMappingAssistantController.MappingAssistantSummary summary = QuickBridgeMappingAssistantController.getSummary(
      null,
      null,
      null
    );
    List<QuickBridgeMappingAssistantController.MappingSuggestion> suggestions = QuickBridgeMappingAssistantController.suggestMappings(
      '',
      '',
      ''
    );
    QuickBridgeMappingAssistantController.MappingReviewResult review = QuickBridgeMappingAssistantController.reviewMappings(
      '',
      '',
      '',
      null
    );
    Test.stopTest();

    Assert.areEqual('Needs Context', summary.status);
    Assert.areEqual(0, suggestions.size());
    Assert.areEqual('Needs Context', review.status);
  }

  private static Boolean hasSuggestion(
    List<QuickBridgeMappingAssistantController.MappingSuggestion> suggestions,
    String salesforceField,
    String externalField
  ) {
    for (
      QuickBridgeMappingAssistantController.MappingSuggestion suggestion : suggestions
    ) {
      if (
        suggestion.salesforceField != null &&
        suggestion.salesforceField.endsWith(salesforceField) &&
        suggestion.externalField == externalField
      ) {
        return true;
      }
    }
    return false;
  }

  private static Boolean hasExternalSuggestion(
    List<QuickBridgeMappingAssistantController.MappingSuggestion> suggestions,
    String externalField
  ) {
    for (
      QuickBridgeMappingAssistantController.MappingSuggestion suggestion : suggestions
    ) {
      if (suggestion.externalField == externalField) {
        return true;
      }
    }
    return false;
  }
}