/*
Class Name: AIDataSourceResultProcessorTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceResultProcessor: turning query results into maps that are safe to give the model.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceResultProcessor: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIDataSourceResultProcessorTest {

    // testScenario1: Records are processed -> they are flattened into maps of their populated fields.
    // testScenario2: A PII field registered for the object is processed -> it is replaced by a substitute and the pair is remembered for the conversation.
    // testScenario3: Child records from a subquery are processed -> they are flattened under their relationship name.
    // testScenario4: A parent lookup is processed -> it is followed and flattened under its relationship name.
    // testScenario5: A field the running user cannot read is processed -> it is left out, so a user is never given more through the model than they could read themselves.
    // testScenario6: Null input, an empty list and a null record in the list are processed -> the first two return an empty list and the null record becomes an empty map.
    // testScenario7: Personal data that is not text (a number here) is processed -> it is masked too, and a missing masking rule is reported once however many values are masked.

    private static final String FAKE_NAME = 'Fake Name';
    private static final String REDACTED_PREFIX = 'REDACTED-';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create two accounts and query them
        List<Account> accounts = AIAssistTestDataFactory.createAccounts(2, true);
        List<Account> queried = [SELECT Id, Name FROM Account WHERE Id IN :accounts ORDER BY Name];
        List<Object> processed;

        // [2] Process the records
        Test.startTest();
            processed = AIDataSourceResultProcessor.processResults(queried, null);
        Test.stopTest();

        // [3] Check each record is flattened to its populated fields
        Assert.areEqual(2, processed.size(), 'One map per record.');
        Assert.areEqual(queried[0].Name, ((Map<String, Object>) processed[0]).get('Name'), 'The populated field is kept.');
        Assert.areEqual(queried[0].Id, ((Map<String, Object>) processed[0]).get('Id'), 'The Id is kept.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent, a conversation and a PII registry for Account
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', true)[0];
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Account', 'Name', AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, true);

        // [2] Give the name field type a substitute rule
        AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
            AIAssistApplicationConstants.PII_FIELD_TYPE_NAME => AIAssistTestDataFactory.createAIPiiMaskingRule(AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST, FAKE_NAME, true)
        };
        AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();

        // [3] Create an account and query it
        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
        List<Account> queried = [SELECT Id, Name FROM Account WHERE Id = :account.Id];
        List<Object> processed;

        // [4] Process the records for the conversation
        Test.startTest();
            processed = AIDataSourceResultProcessor.processResults(queried, conversation.Id);
        Test.stopTest();

        // [5] Read the remembered substitute for the real name
        String rememberedFakeValue = AIPiiMappingService.getFakeValue(conversation.Id, queried[0].Name);

        // [6] Check the name is replaced and the pair is remembered
        Assert.areEqual(FAKE_NAME, ((Map<String, Object>) processed[0]).get('Name'), 'The real name never reaches the model.');
        Assert.areEqual(FAKE_NAME, rememberedFakeValue, 'The pair is remembered so the reply can be restored.');
    }

    @IsTest static void testScenario3() {

        // [1] Create an account with two contacts and query them as a subquery
        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
        insert new Contact(LastName = 'Child One', AccountId = account.Id);
        insert new Contact(LastName = 'Child Two', AccountId = account.Id);

        List<Account> queried = [SELECT Id, (SELECT Id, LastName FROM Contacts) FROM Account WHERE Id = :account.Id];

        List<Object> processed;

        // [2] Process the records
        Test.startTest();
            processed = AIDataSourceResultProcessor.processResults(queried, null);
        Test.stopTest();

        // [3] Pull the child records out of the result
        List<Object> children = (List<Object>) ((Map<String, Object>) processed[0]).get('Contacts');

        // [4] Check both children are flattened under their relationship name
        Assert.areEqual(2, children.size(), 'Both children are flattened.');
        Assert.isNotNull(((Map<String, Object>) children[0]).get('LastName'), 'Each child keeps its fields.');
    }

    @IsTest static void testScenario4() {

        // [1] Create a contact with a parent account and query the parent name
        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];

        Contact contact = new Contact(LastName = 'Has Parent', AccountId = account.Id);
        insert contact;

        List<Contact> queried = [SELECT Id, LastName, Account.Name FROM Contact WHERE Id = :contact.Id];

        List<Object> processed;

        // [2] Process the records
        Test.startTest();
            processed = AIDataSourceResultProcessor.processResults(queried, null);
        Test.stopTest();

        // [3] Read the parent map and the real account name
        Map<String, Object> parent = (Map<String, Object>) ((Map<String, Object>) processed[0]).get('Account');
        String accountName = [SELECT Name FROM Account WHERE Id = :account.Id].Name;

        // [4] Check the parent is followed and flattened
        Assert.areEqual(accountName, parent.get('Name'), 'The parent is followed.');
    }

    @IsTest static void testScenario5() {

        // [1] Create a chat user with the AI Assist User permission set
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
        AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

        // [2] Create an agent and query fields the user cannot read
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
        List<AIAgent__c> queried = [SELECT Id, Name, AccessMode__c, MaxMessagesPerConversation__c FROM AIAgent__c WHERE Id = :agent.Id WITH SYSTEM_MODE];
        List<Object> processed;

        // [3] Process the records as the chat user
        System.runAs(chatUser) {

            Test.startTest();
                processed = AIDataSourceResultProcessor.processResults(queried, null);
            Test.stopTest();
        }

        // [4] Take the flattened record from the result
        Map<String, Object> flattened = (Map<String, Object>) processed[0];

        // [5] Check unreadable fields are left out
        Assert.isTrue(flattened.containsKey('Id'), 'A readable field is kept.');
        Assert.isFalse(flattened.containsKey('LoomConnect__AccessMode__c') || flattened.containsKey('AccessMode__c'), 'The AI Assist User permission set cannot read the access mode, so it is left out.');
        Assert.isFalse(flattened.containsKey('LoomConnect__MaxMessagesPerConversation__c') || flattened.containsKey('MaxMessagesPerConversation__c'), 'Nor the message cap.');
    }

    @IsTest static void testScenario6() {

        // [1] Create an account and a list that holds a null record
        Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];

        List<SObject> recordsWithNull = new List<SObject>{
            null,
            account
        };

        List<Object> fromNull;
        List<Object> fromEmpty;
        List<Object> withNullRecord;

        // [2] Process null input, an empty list and the list with a null record
        Test.startTest();
            fromNull = AIDataSourceResultProcessor.processResults(null, null);
            fromEmpty = AIDataSourceResultProcessor.processResults(new List<SObject>(), null);
            withNullRecord = AIDataSourceResultProcessor.processResults(recordsWithNull, null);
        Test.stopTest();

        // [3] Check empty input gives nothing and the null record becomes an empty map
        Assert.isTrue(fromNull.isEmpty() && fromEmpty.isEmpty(), 'Nothing in, nothing out.');
        Assert.areEqual(2, withNullRecord.size(), 'The null entry keeps its place.');
        Assert.isTrue(((Map<String, Object>) withNullRecord[0]).isEmpty(), 'And is empty.');
    }

    @IsTest static void testScenario7() {

        // [1] Create an agent, a conversation and a PII registry for a numeric Account field
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'Account', true)[0];
        AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, 'Account', 'NumberOfEmployees', AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, true);

        // [2] Leave the masking rules empty so the rule is missing
        AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>();
        AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();

        // [3] Create three accounts with employee counts and query them
        List<Account> accounts = AIAssistTestDataFactory.createAccounts(3, false);
        accounts[0].NumberOfEmployees = 1201;
        accounts[1].NumberOfEmployees = 1202;
        accounts[2].NumberOfEmployees = 1203;
        insert accounts;

        List<Account> queried = [SELECT Id, NumberOfEmployees FROM Account WHERE Id IN :accounts];

        List<Object> processed;

        // [4] Process the records for the conversation
        Test.startTest();
            processed = AIDataSourceResultProcessor.processResults(queried, conversation.Id);
        Test.stopTest();

        // [5] Collect the stand-in values, checking each number is replaced
        Set<String> standIns = new Set<String>();
        for (Object processedRecord : processed) {

            Object sentValue = ((Map<String, Object>) processedRecord).get('NumberOfEmployees');
            Assert.isTrue(sentValue instanceof String && ((String) sentValue).startsWith(REDACTED_PREFIX), 'The number is replaced, not passed on.');
            standIns.add((String) sentValue);
        }

        // [6] Restore one stand-in and count the missing-rule logs
        String restoredValue = AIPiiPseudonymizationService.restore(conversation.Id, (String) ((Map<String, Object>) processed[0]).get('NumberOfEmployees'));
        Integer missingRuleLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIPiiPseudonymizationService'];

        // [7] Check the stand-ins are unique, restorable and the missing rule logged once
        Assert.areEqual(3, standIns.size(), 'Each value has its own stand-in.');
        Assert.isTrue(new Set<String>{ '1201', '1202', '1203' }.contains(restoredValue), 'The real value can be restored from its text form.');
        Assert.areEqual(1, missingRuleLogCount, 'The missing rule is reported once, not once per value.');
    }
}
