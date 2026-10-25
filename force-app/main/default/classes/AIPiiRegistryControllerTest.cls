/*
Class Name: AIPiiRegistryControllerTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistryController: the Apex calls of the AI PII Registry tab.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistryController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistryControllerTest {

    // testScenario1: A manager reads, adds, syncs, switches and overrides through the controller -> each call returns what the service returns.
    // testScenario2: A user without the Manage Settings permission calls the controller -> the access label is shown, and nothing is logged for it.
    // testScenario3: A manager asks for an object that does not exist -> the not found label is shown.
    // testScenario4: A call fails on the platform -> the generic label is shown and the error is logged once.

    private static final String CONTACT = 'Contact';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact with a PII field, and create a contact
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIPIIFieldMetadata__c field = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'Email', AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true)[0];
            Contact record = new Contact(LastName = 'Realname', Email = 'real.person@example.com');
            insert record;

            // [2] Call each method
            Test.startTest();
                AIPiiRegistryDataStructure.RegistryPage page = AIPiiRegistryController.getRegistryPage();
                AIPiiRegistryDataStructure.RegistryDetail detail = AIPiiRegistryController.getRegistryDetail(registry.Id);
                List<AIPiiRegistryDataStructure.RegistryView> views = AIPiiRegistryController.getRegistryViews();
                List<AIPiiRegistryDataStructure.ObjectOption> options = AIPiiRegistryController.getObjectOptions('opportun');
                AIPiiRegistryDataStructure.RegistryView off = AIPiiRegistryController.setRegistryActive(registry.Id, false);
                AIPiiRegistryDataStructure.FieldView overridden = AIPiiRegistryController.saveFieldOverride(field.Id, true, AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER);
                AIPiiRegistryDataStructure.FieldView reset = AIPiiRegistryController.resetFieldOverride(field.Id);
                AIPiiRegistryDataStructure.MaskingTestResult testResult = AIPiiRegistryController.runMaskingTest(registry.Id, record.Id);
                AIPiiRegistryDataStructure.RegistryView added = AIPiiRegistryController.addRegistryObject('Account', 500);
                AIPiiRegistryDataStructure.RegistryView synced = AIPiiRegistryController.syncRegistry(registry.Id, null);
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(1, page.registries.size(), 'The page lists the registry.');
            Assert.areEqual(1, detail.fields.size(), 'The pane has the field.');
            Assert.areEqual(1, views.size(), 'The views list the registry.');
            Assert.isFalse(options.isEmpty(), 'The search found Opportunity.');
            Assert.isFalse(off.isActive, 'The registry was switched off.');
            Assert.isTrue(overridden.isOverridden, 'The field was overridden.');
            Assert.isFalse(reset.isOverridden, 'And reset.');
            Assert.isNotNull(testResult, 'The test ran.');
            Assert.areEqual('Account', added.objectApiName, 'Account was added.');
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED, synced.syncStatus, 'The sync was queued.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String refusal;

            // [2] Call the controller as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIPiiRegistryController.getRegistryPage();
                    } catch (AuraHandledException ex) {

                        refusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label should be shown.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'A refusal is not an error, so nothing should be logged.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the Id of a registry that was never saved
            Id missingId = AIPIIRegistry__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001AAA';
            String refusal;

            // [2] Ask for its pane
            Test.startTest();
                try {

                    AIPiiRegistryController.getRegistryDetail(missingId);
                } catch (AuraHandledException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_PiiRegistry_Error_Not_Found, refusal, 'The not found label should be shown.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register a field, and offer a type whose name is longer than the field holds, which the platform refuses on save
            String longType = 'x'.repeat(60);
            AIPiiRegistryEditorService.typeOptionsForTest = new List<AIPiiRegistryDataStructure.TypeOption>{ AIAssistTestDataFactory.createAIPiiTypeOption(longType, null, 'Redacted') };
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIPIIFieldMetadata__c field = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'Email', null, true)[0];
            String refusal;

            // [2] Override the field with that type
            Test.startTest();
                try {

                    AIPiiRegistryController.saveFieldOverride(field.Id, true, longType);
                } catch (AuraHandledException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Read the log
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Generic, refusal, 'The generic label should be shown.');
            Assert.areEqual(1, logs.size(), 'The error should be logged once.');
            Assert.areEqual('AIPiiRegistryController', logs[0].ClassName__c, 'The log should name the controller.');
            Assert.areEqual('saveFieldOverride', logs[0].MethodName__c, 'The log should name the method.');
        }
    }
}
