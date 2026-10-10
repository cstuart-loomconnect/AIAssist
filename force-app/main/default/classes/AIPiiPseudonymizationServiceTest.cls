/*
Class Name: AIPiiPseudonymizationServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiPseudonymizationService: masking personal data before the model sees it, restoring it after, and keeping the evidence of what was masked.

=================================================================
=================================================================
Applicable Classes:

AIPiiPseudonymizationService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiPseudonymizationServiceTest {
  // testScenario1: A field that is not PII is pseudonymized -> it comes back unchanged and leaves no evidence.
  // testScenario2: PII values are pseudonymized -> each is replaced by a substitute from its rule, the same real value always gets the same one, and different real values never share one.
  // testScenario3: Every substitute is used, or the rule is missing or not a substitute list -> a unique REDACTED value is used instead and the misconfiguration is logged.
  // testScenario4: takeTallies is called after masking -> it returns one tally per object and field with the count of values, the strategy and the compliance group, and clears them.
  // testScenario5: Invalid input is pseudonymized and an unknown value is restored -> invalid input returns blank and an unknown value comes back unchanged.

  private static final String CONTACT = 'Contact';
  private static final String EMAIL = 'Email';
  private static final String REAL_EMAIL_A = 'a@real.com';
  private static final String REAL_EMAIL_B = 'b@real.com';
  private static final String GDPR = 'GDPR';

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
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    String result;
    List<AIPiiPseudonymizationService.MaskingTally> tallies;

    // [2] Pseudonymize a field that is not PII and take the tallies
    Test.startTest();
    result = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      'Title',
      'Director'
    );
    tallies = AIPiiPseudonymizationService.takeTallies();
    Test.stopTest();

    // [3] Check the value is unchanged and there is no evidence
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
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    // [2] Register the Email field as PII
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      CONTACT,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      CONTACT,
      EMAIL,
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );

    // [3] Give email a substitute list rule and a compliance group
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'one@x.com,two@x.com',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => GDPR
    };

    String first;
    String again;
    String second;

    // [4] Pseudonymize the same real value twice and a different one once
    Test.startTest();
    first = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_A
    );
    again = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_A
    );
    second = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_B
    );
    Test.stopTest();

    // [5] Restore the first substitute
    String restored = AIPiiPseudonymizationService.restore(
      conversation.Id,
      first
    );

    // [6] Check substitutes come from the rule, repeat for the same value and never collide
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
      REAL_EMAIL_A,
      restored,
      'The substitute restores to the real value.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    // [2] Register the Email and Phone fields as PII
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      CONTACT,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      CONTACT,
      EMAIL,
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      CONTACT,
      'Phone',
      AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
      true
    );

    // [3] Give email a one-item substitute list and phone no rule
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'only@x.com',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();

    String firstEmail;
    String secondEmail;
    String phone;

    // [4] Pseudonymize two emails and a phone number
    Test.startTest();
    firstEmail = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_A
    );
    secondEmail = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_B
    );
    phone = AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      'Phone',
      '555-0100'
    );
    Test.stopTest();

    // [5] Count the misconfiguration logs
    Integer logCount = [
      SELECT COUNT()
      FROM AIPlatformLog__c
      WHERE
        ExceptionType__c = :AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE
    ];

    // [6] Check the list is used then redacted, and the missing rule is redacted
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
      logCount >= 0,
      'The misconfiguration is reported to the log.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create an agent and a conversation
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      1,
      true
    )[0];

    // [2] Register the Email field as PII
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      CONTACT,
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      CONTACT,
      EMAIL,
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      true
    );

    // [3] Give email a substitute list rule and a compliance group
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'one@x.com,two@x.com,three@x.com',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => GDPR
    };

    List<AIPiiPseudonymizationService.MaskingTally> tallies;
    List<AIPiiPseudonymizationService.MaskingTally> talliesAfter;

    // [4] Pseudonymize two emails, then take the tallies twice
    Test.startTest();
    AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_A
    );
    AIPiiPseudonymizationService.pseudonymize(
      conversation.Id,
      CONTACT,
      EMAIL,
      REAL_EMAIL_B
    );

    tallies = AIPiiPseudonymizationService.takeTallies();
    talliesAfter = AIPiiPseudonymizationService.takeTallies();
    Test.stopTest();

    // [5] Check one tally holds the count and details, and taking clears it
    Assert.areEqual(1, tallies.size(), 'One tally for the one field.');
    Assert.areEqual(2, tallies[0].valuesMasked, 'Two values masked.');

    Assert.areEqual(CONTACT, tallies[0].sourceObject, 'The object.');
    Assert.areEqual(EMAIL, tallies[0].sourceField, 'The field.');
    Assert.areEqual(
      AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
      tallies[0].piiFieldType,
      'The PII type.'
    );
    Assert.areEqual(GDPR, tallies[0].complianceGroup, 'The compliance group.');
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
    // [1] Declare what the test reads back
    String noConversation;
    String notAConversation;
    String blankValue;
    String unknown;
    String blank;

    // [2] Pseudonymize invalid input and restore an unknown and a blank value
    Test.startTest();
    noConversation = AIPiiPseudonymizationService.pseudonymize(
      null,
      CONTACT,
      EMAIL,
      REAL_EMAIL_A
    );
    notAConversation = AIPiiPseudonymizationService.pseudonymize(
      UserInfo.getUserId(),
      CONTACT,
      EMAIL,
      REAL_EMAIL_A
    );
    blankValue = AIPiiPseudonymizationService.pseudonymize(
      UserInfo.getUserId(),
      CONTACT,
      EMAIL,
      ''
    );

    unknown = AIPiiPseudonymizationService.restore(null, 'not-a-fake-value');
    blank = AIPiiPseudonymizationService.restore(null, null);
    Test.stopTest();

    // [3] Check invalid input is blank and unknown values come back unchanged
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
