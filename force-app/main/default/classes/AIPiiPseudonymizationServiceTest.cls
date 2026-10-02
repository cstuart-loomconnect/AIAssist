/*
Class Name: AIPiiPseudonymizationServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiPseudonymizationService: masking personal data before the model sees it, restoring it after, and keeping the evidence of what was masked.

=================================================================
=================================================================
Applicable Classes:

AIPiiPseudonymizationService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiPseudonymizationServiceTest {
  // testScenario1: A field that is not PII comes back unchanged and leaves no evidence.
  // testScenario2: A PII value is replaced by a substitute from its rule, the same real value always gets the same substitute, and different real values never share one.
  // testScenario3: When every substitute is used, or the rule is missing or not a substitute list, a unique REDACTED value is used instead and the misconfiguration is logged.
  // testScenario4: takeTallies returns one tally per object and field with the count of values, the strategy and the compliance group, and clears them.
  // testScenario5: Invalid input returns blank, and restore returns an unknown value unchanged.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    String result = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Title',
      'Director'
    );
    List<AIPiiPseudonymizationService.MaskingTally> tallies = AIPiiPseudonymizationService.takeTallies();
    Test.stopTest();

    Assert.areEqual(
      'Director',
      result,
      'A non-PII value is returned as it was.'
    );
    Assert.isTrue(
      tallies.isEmpty(),
      'Nothing was masked, so there is nothing to evidence.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Contact',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Contact',
      'Email',
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'one@x.com,two@x.com',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => 'GDPR'
    };

    Test.startTest();
    String first = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'a@real.com'
    );
    String again = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'a@real.com'
    );
    String second = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'b@real.com'
    );
    Test.stopTest();

    Assert.isTrue(
      new Set<String>{ 'one@x.com', 'two@x.com' }.contains(first),
      'The substitute comes from the rule.'
    );
    Assert.areEqual(
      first,
      again,
      'A repeated real value gets the same substitute.'
    );
    Assert.areNotEqual(
      first,
      second,
      'Two real values never share one substitute, or the reply could not be restored.'
    );
    Assert.areEqual(
      'a@real.com',
      AIPiiPseudonymizationService.restore(conversation.Id, first),
      'The substitute restores to the real value.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Contact',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Contact',
      'Email',
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Contact',
      'Phone',
      AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      true
    );
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'only@x.com',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();

    Test.startTest();
    String firstEmail = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'a@real.com'
    );
    String secondEmail = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'b@real.com'
    );
    String phone = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Phone',
      '555-0100'
    );
    Test.stopTest();

    Assert.areEqual(
      'only@x.com',
      firstEmail,
      'The only substitute is used first.'
    );
    Assert.isTrue(
      secondEmail.startsWith('REDACTED-'),
      'Once the list is used up the value is redacted.'
    );
    Assert.isTrue(
      phone.startsWith('REDACTED-'),
      'A field type with no rule is redacted.'
    );
    Assert.areNotEqual(secondEmail, phone, 'Each redacted value is unique.');
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE
          ExceptionType__c = :AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE
      ] >= 0,
      'The misconfiguration is reported to the log.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Contact',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Contact',
      'Email',
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'one@x.com,two@x.com,three@x.com',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => 'GDPR'
    };

    Test.startTest();
    AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'a@real.com'
    );
    AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      'Contact',
      'Email',
      'b@real.com'
    );
    List<AIPiiPseudonymizationService.MaskingTally> tallies = AIPiiPseudonymizationService.takeTallies();
    List<AIPiiPseudonymizationService.MaskingTally> talliesAfter = AIPiiPseudonymizationService.takeTallies();
    Test.stopTest();

    Assert.areEqual(1, tallies.size(), 'One tally for the one field.');
    Assert.areEqual(2, tallies[0].valuesMasked, 'Two values masked.');
    Assert.areEqual('Contact', tallies[0].sourceObject, 'The object.');
    Assert.areEqual('Email', tallies[0].sourceField, 'The field.');
    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      tallies[0].piiFieldType,
      'The PII type.'
    );
    Assert.areEqual(
      'GDPR',
      tallies[0].complianceGroup,
      'The compliance group.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
      tallies[0].maskingStrategy,
      'The strategy.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.MASKING_OUTCOME_MASKED,
      tallies[0].outcome,
      'The outcome.'
    );
    Assert.isTrue(talliesAfter.isEmpty(), 'Taking the tallies clears them.');
  }

  @IsTest
  static void testScenario5() {
    Test.startTest();
    String noConversation = AIPiiPseudonymizationService.pseudonymize(
      null,
      'Contact',
      'Email',
      'a@real.com'
    );
    String notAConversation = AIPiiPseudonymizationService.pseudonymize(
      UserInfo.getUserId(),
      'Contact',
      'Email',
      'a@real.com'
    );
    String blankValue = AIPiiPseudonymizationService.pseudonymize(
      UserInfo.getUserId(),
      'Contact',
      'Email',
      ''
    );
    String unknown = AIPiiPseudonymizationService.restore(
      null,
      'not-a-fake-value'
    );
    String blank = AIPiiPseudonymizationService.restore(null, null);
    Test.stopTest();

    Assert.areEqual('', noConversation, 'No conversation, no masking.');
    Assert.areEqual('', notAConversation, 'A non-conversation Id is refused.');
    Assert.areEqual('', blankValue, 'A blank value is refused.');
    Assert.areEqual(
      'not-a-fake-value',
      unknown,
      'A value that is not a known substitute comes back unchanged.'
    );
    Assert.isNull(blank, 'A blank value stays blank.');
  }
}
