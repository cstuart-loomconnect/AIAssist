/*
Class Name: AIDataSourceResultProcessorTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceResultProcessor: turning query results into maps that are safe to give the model.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceResultProcessor

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIDataSourceResultProcessorTest {
  // testScenario1: Records are flattened into maps of their populated fields.
  // testScenario2: A PII field registered for the object is replaced by a substitute and the pair is remembered for the conversation.
  // testScenario3: Child records from a subquery are flattened under their relationship name.
  // testScenario4: A parent lookup is followed and flattened under its relationship name.
  // testScenario5: A field the running user cannot read is left out, so a user is never given more through the model than they could read themselves.
  // testScenario6: Null input and an empty list return an empty list, and a null record in the list becomes an empty map.
  // testScenario7: Personal data that is not text (a number here) is masked too, and a missing masking rule is reported once however many values are masked.

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
    List<Account> accounts = AIAssistTestDataFactory.createAccounts(2, true);
    List<Account> queried = [
      SELECT Id, Name
      FROM Account
      WHERE Id IN :accounts
      ORDER BY Name
    ];

    Test.startTest();
    List<Object> processed = AIDataSourceResultProcessor.processResults(
      queried,
      null
    );
    Test.stopTest();

    Assert.areEqual(2, processed.size(), 'One map per record.');
    Assert.areEqual(
      queried[0].Name,
      ((Map<String, Object>) processed[0]).get('Name'),
      'The populated field is kept.'
    );
    Assert.areEqual(
      queried[0].Id,
      ((Map<String, Object>) processed[0]).get('Id'),
      'The Id is kept.'
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
      'Account',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Account',
      'Name',
      AIAssistApplicationConstants.PII_FIELD_TYPE_NAME,
      true
    );
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
      AIAssistApplicationConstants.PII_FIELD_TYPE_NAME => AIAssistTestDataFactory.createAIPiiMaskingRule(
        AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST,
        'Fake Name',
        true
      )
    };
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();
    Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
    List<Account> queried = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :account.Id
    ];

    Test.startTest();
    List<Object> processed = AIDataSourceResultProcessor.processResults(
      queried,
      conversation.Id
    );
    Test.stopTest();

    Assert.areEqual(
      'Fake Name',
      ((Map<String, Object>) processed[0]).get('Name'),
      'The real name never reaches the model.'
    );
    Assert.areEqual(
      'Fake Name',
      AIPiiMappingService.getFakeValue(conversation.Id, queried[0].Name),
      'The pair is remembered so the reply can be restored.'
    );
  }

  @IsTest
  static void testScenario3() {
    Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
    insert new Contact(LastName = 'Child One', AccountId = account.Id);
    insert new Contact(LastName = 'Child Two', AccountId = account.Id);
    List<Account> queried = [
      SELECT Id, (SELECT Id, LastName FROM Contacts)
      FROM Account
      WHERE Id = :account.Id
    ];

    Test.startTest();
    List<Object> processed = AIDataSourceResultProcessor.processResults(
      queried,
      null
    );
    Test.stopTest();

    List<Object> children = (List<Object>) ((Map<String, Object>) processed[0])
      .get('Contacts');

    Assert.areEqual(2, children.size(), 'Both children are flattened.');
    Assert.isNotNull(
      ((Map<String, Object>) children[0]).get('LastName'),
      'Each child keeps its fields.'
    );
  }

  @IsTest
  static void testScenario4() {
    Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
    Contact contact = new Contact(
      LastName = 'Has Parent',
      AccountId = account.Id
    );
    insert contact;
    List<Contact> queried = [
      SELECT Id, LastName, Account.Name
      FROM Contact
      WHERE Id = :contact.Id
    ];

    Test.startTest();
    List<Object> processed = AIDataSourceResultProcessor.processResults(
      queried,
      null
    );
    Test.stopTest();

    Map<String, Object> parent = (Map<String, Object>) ((Map<String, Object>) processed[0])
      .get('Account');

    Assert.areEqual(
      [SELECT Name FROM Account WHERE Id = :account.Id].Name,
      parent.get('Name'),
      'The parent is followed.'
    );
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    List<AIAgent__c> queried = [
      SELECT Id, Name, AccessMode__c, MaxMessagesPerConversation__c
      FROM AIAgent__c
      WHERE Id = :agent.Id
      WITH SYSTEM_MODE
    ];
    List<Object> processed;

    System.runAs(chatUser) {
      Test.startTest();
      processed = AIDataSourceResultProcessor.processResults(queried, null);
      Test.stopTest();
    }

    Map<String, Object> flattened = (Map<String, Object>) processed[0];

    Assert.isTrue(flattened.containsKey('Id'), 'A readable field is kept.');
    Assert.isFalse(
      flattened.containsKey('LoomConnect__AccessMode__c') ||
      flattened.containsKey('AccessMode__c'),
      'The AI Assist User permission set cannot read the access mode, so it is left out.'
    );
    Assert.isFalse(
      flattened.containsKey('LoomConnect__MaxMessagesPerConversation__c') ||
      flattened.containsKey('MaxMessagesPerConversation__c'),
      'Nor the message cap.'
    );
  }

  @IsTest
  static void testScenario6() {
    Test.startTest();
    List<Object> fromNull = AIDataSourceResultProcessor.processResults(
      null,
      null
    );
    List<Object> fromEmpty = AIDataSourceResultProcessor.processResults(
      new List<SObject>(),
      null
    );
    List<Object> withNullRecord = AIDataSourceResultProcessor.processResults(
      new List<SObject>{
        null,
        AIAssistTestDataFactory.createAccounts(1, true)[0]
      },
      null
    );
    Test.stopTest();

    Assert.isTrue(
      fromNull.isEmpty() && fromEmpty.isEmpty(),
      'Nothing in, nothing out.'
    );
    Assert.areEqual(
      2,
      withNullRecord.size(),
      'The null entry keeps its place.'
    );
    Assert.isTrue(
      ((Map<String, Object>) withNullRecord[0]).isEmpty(),
      'And is empty.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Account',
      true
    )[0];
    AIAssistTestDataFactory.createAIPIIFieldMetadata(
      registry.Id,
      'Account',
      'NumberOfEmployees',
      AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER,
      true
    );
    AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>(); // No rule for the type.
    AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();
    List<Account> accounts = AIAssistTestDataFactory.createAccounts(3, false);
    accounts[0].NumberOfEmployees = 1201;
    accounts[1].NumberOfEmployees = 1202;
    accounts[2].NumberOfEmployees = 1203;
    insert accounts;
    List<Account> queried = [
      SELECT Id, NumberOfEmployees
      FROM Account
      WHERE Id IN :accounts
    ];

    Test.startTest();
    List<Object> processed = AIDataSourceResultProcessor.processResults(
      queried,
      conversation.Id
    );
    Test.stopTest();

    Set<String> standIns = new Set<String>();
    for (Object processedRecord : processed) {
      Object sentValue = ((Map<String, Object>) processedRecord)
        .get('NumberOfEmployees');
      Assert.isTrue(
        sentValue instanceof String &&
        ((String) sentValue).startsWith('REDACTED-'),
        'The number is replaced, not passed on.'
      );
      standIns.add((String) sentValue);
    }
    Assert.areEqual(3, standIns.size(), 'Each value has its own stand-in.');
    String restoredValue = AIPiiPseudonymizationService.restore(
      conversation.Id,
      (String) ((Map<String, Object>) processed[0]).get('NumberOfEmployees')
    );
    Assert.isTrue(
      new Set<String>{ '1201', '1202', '1203' }.contains(restoredValue),
      'The real value can be restored from its text form.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIPiiPseudonymizationService'
      ],
      'The missing rule is reported once, not once per value.'
    );
  }
}
