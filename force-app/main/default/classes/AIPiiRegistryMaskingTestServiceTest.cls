/*
Class Name: AIPiiRegistryMaskingTestServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistryMaskingTestService: the masking test of the AI PII Registry tab, which shows what would be sent for a record and saves nothing.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistryMaskingTestService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistryMaskingTestServiceTest {

    // testScenario1: A manager tests a Contact -> each PII field that holds a value shows its real value, a substitute from its rule and the rule, and nothing is saved.
    // testScenario2: The record is another object, there is no record, or it cannot be read -> the test is refused.
    // testScenario3: The object has no PII fields, or the fields are empty on the record -> no rows come back.
    // testScenario4: A user without the Manage Settings permission calls the service -> the access label is shown.

    private static final String CONTACT = 'Contact';
    private static final String EMAIL = 'Email';
    private static final String REAL_EMAIL = 'real.person@example.com';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact with Email and LastName as PII and Title as not PII, and give Email a substitute list and LastName none
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, EMAIL, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true);
            AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'LastName', AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, true);
            AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'Title', null, true);
            AIPiiPseudonymizationService.ruleByFieldType = new Map<String, AIPiiDataMaskingRule__mdt>{
                AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL => AIAssistTestDataFactory.createAIPiiMaskingRule(AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST, 'sub@example.invalid', true)
            };
            AIPiiPseudonymizationService.complianceGroupByFieldType = new Map<String, String>();
            Contact record = new Contact(LastName = 'Realname', Email = REAL_EMAIL, Title = 'Director');
            insert record;

            // [2] Run the masking test for the record
            Test.startTest();
                AIPiiRegistryDataStructure.MaskingTestResult result = AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, record.Id);
            Test.stopTest();

            // [3] Read back what a real masking would have saved
            Integer mappingCount = [SELECT COUNT() FROM AIPIIMapping__c];
            Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

            // [4] Check the rows
            Assert.areEqual(2, result.rows.size(), 'Email and LastName are masked, Title is not PII.');
            AIPiiRegistryDataStructure.MaskingTestRow emailRow = result.rows[0].fieldLabel == EMAIL ? result.rows[0] : result.rows[1];
            AIPiiRegistryDataStructure.MaskingTestRow nameRow = result.rows[0].fieldLabel == EMAIL ? result.rows[1] : result.rows[0];
            Assert.areEqual(REAL_EMAIL, emailRow.realValue, 'The real value is shown to the administrator.');
            Assert.areEqual('sub@example.invalid', emailRow.sentValue, 'The substitute comes from the rule.');
            Assert.areEqual(AIAssistApplicationConstants.PII_MASKING_STRATEGY_SUBSTITUTE_FROM_LIST, emailRow.ruleText, 'The rule is named.');
            Assert.isTrue(nameRow.sentValue.startsWith('REDACTED-'), 'A type with no rule is redacted.');
            Assert.areEqual(Label.AI_PiiRegistry_Rule_Redacted_No_Rule, nameRow.ruleText, 'And says so.');
            Assert.areEqual(0, mappingCount, 'Nothing was saved.');
            Assert.areEqual(0, logCount, 'Nothing was logged.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact, and create an account and a contact that is then deleted
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, EMAIL, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true);
            Account account = new Account(Name = 'Test account');
            insert account;
            Contact deletedContact = new Contact(LastName = 'Gone', Email = REAL_EMAIL);
            insert deletedContact;
            delete deletedContact;
            List<String> refusals = new List<String>();

            // [2] Test with an account, with no record, and with the deleted contact
            Test.startTest();
                try {

                    AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, account.Id);
                } catch (AIPiiRegistryMaskingTestService.AIPiiRegistryMaskingTestServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, null);
                } catch (AIPiiRegistryMaskingTestService.AIPiiRegistryMaskingTestServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, deletedContact.Id);
                } catch (AIPiiRegistryMaskingTestService.AIPiiRegistryMaskingTestServiceException ex) {

                    refusals.add(ex.getMessage());
                }
            Test.stopTest();

            // [3] Check the refusals
            Assert.areEqual(3, refusals.size(), 'All three were refused.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Test_Record_Invalid, refusals[0], 'An account is not a contact.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Test_Record_Invalid, refusals[1], 'No record is refused.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Test_Record_Not_Found, refusals[2], 'A deleted record cannot be read.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact with no PII fields and create a contact with no email
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'Title', null, true);
            Contact record = new Contact(LastName = 'Realname');
            insert record;

            // [2] Test the record with no PII fields, then add an Email field and test again
            Test.startTest();
                AIPiiRegistryDataStructure.MaskingTestResult noPiiResult = AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, record.Id);
                AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, EMAIL, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true);
                AIPiiRegistryDataStructure.MaskingTestResult emptyResult = AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, record.Id);
            Test.stopTest();

            // [3] Check no rows came back either time
            Assert.isTrue(noPiiResult.rows.isEmpty(), 'There is nothing to mask.');
            Assert.isTrue(emptyResult.rows.isEmpty(), 'An empty field has nothing to mask.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set, and a registry
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            String refusal;

            // [2] Call the service as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIPiiRegistryMaskingTestService.runMaskingTest(registry.Id, UserInfo.getUserId());
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label is shown.');
        }
    }
}
