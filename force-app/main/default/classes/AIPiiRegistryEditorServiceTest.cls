/*
Class Name: AIPiiRegistryEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistryEditorService: the registry list, the object pane, adding, syncing, switching and the field overrides behind the AI PII Registry tab.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistryEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistryEditorServiceTest {

    // testScenario1: A manager reads the page -> the objects come back in name order with their field and PII counts, the limit comes from the setting, and the built-in types are offered.
    // testScenario2: A manager reads the pane of an object -> the PII fields come first, and a failed sync says whether the object has more fields than the limit and what limit to try next.
    // testScenario3: A manager adds an object -> it is saved queued with the limit, the sync runs, and the object, a duplicate, a full registry and a bad limit are refused when they should be.
    // testScenario4: A manager switches an object off and on and syncs it -> the switch is saved, a sync raises the limit and queues, and one already queued is refused.
    // testScenario5: A manager overrides a field -> it is marked overridden with the chosen type and group, a type that is not offered is refused, and a blank type becomes Other.
    // testScenario6: A manager resets an overridden field -> it goes back to the automatic rules and is no longer overridden.
    // testScenario7: A user without the Manage Settings permission calls the service -> the access label is shown.

    private static final String ACCOUNT = 'Account';
    private static final String CONTACT = 'Contact';
    private static final String CONTACT_DETAILS = 'Contact details';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact with two fields, one PII, and Account with none, and set the limit
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.MaxPIIRegistryObjects__c = 7;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { upsert settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIPIIRegistry__c contactRegistry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIAssistTestDataFactory.createAIPIIFieldMetadata(contactRegistry.Id, CONTACT, 'Email', AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true);
            AIAssistTestDataFactory.createAIPIIFieldMetadata(contactRegistry.Id, CONTACT, 'Title', null, true);
            AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, true);

            // [2] Read the page
            Test.startTest();
                AIPiiRegistryDataStructure.RegistryPage page = AIPiiRegistryEditorService.getRegistryPage();
            Test.stopTest();

            // [3] Check the list, the counts, the limit and the types
            Assert.areEqual(2, page.registries.size(), 'Both objects are listed.');
            Assert.areEqual(ACCOUNT, page.registries[0].objectApiName, 'In name order.');
            Assert.areEqual(0, page.registries[0].fieldCount, 'Account has no fields yet.');
            Assert.areEqual(2, page.registries[1].fieldCount, 'Contact has two fields.');
            Assert.areEqual(1, page.registries[1].piiCount, 'One of them is PII.');
            Assert.areEqual(AIAssistApplicationConstants.DEFAULT_MAX_PII_FIELDS_TO_QUERY, page.registries[1].maxFieldsToQuery, 'A blank limit shows the default.');
            Assert.areEqual(7, page.registryLimit, 'The limit is the setting.');
            Assert.isFalse(page.typeOptions.isEmpty(), 'Types are offered.');
            Assert.isNotNull(page.unprotectedObjects, 'The unprotected list is there.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Account as Failed with a limit of three, a PII field and a plain one, and an object that does not exist as Failed
            AIPIIRegistry__c accountRegistry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            accountRegistry.MaxFieldsToQuery__c = 3;
            accountRegistry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
            AIPIIRegistry__c missingRegistry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'No_Such_Object__c', false)[0];
            missingRegistry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
            AIPIIRegistry__c largestRegistry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, false)[0];
            largestRegistry.MaxFieldsToQuery__c = 500;
            insert new List<AIPIIRegistry__c>{ accountRegistry, missingRegistry, largestRegistry };

            AIAssistTestDataFactory.createAIPIIFieldMetadata(accountRegistry.Id, ACCOUNT, 'Name', null, true);
            AIAssistTestDataFactory.createAIPIIFieldMetadata(accountRegistry.Id, ACCOUNT, 'Phone', AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, true);

            // [2] Read the three panes
            Test.startTest();
                AIPiiRegistryDataStructure.RegistryDetail accountDetail = AIPiiRegistryEditorService.getRegistryDetail(accountRegistry.Id);
                AIPiiRegistryDataStructure.RegistryDetail missingDetail = AIPiiRegistryEditorService.getRegistryDetail(missingRegistry.Id);
                AIPiiRegistryDataStructure.RegistryDetail largestDetail = AIPiiRegistryEditorService.getRegistryDetail(largestRegistry.Id);
            Test.stopTest();

            // [3] Check the order, the reason and the next limit
            Assert.areEqual('Phone', accountDetail.fields[0].fieldApiName, 'The PII field comes first.');
            Assert.isTrue(accountDetail.fields[0].isPii, 'It is PII.');
            Assert.isTrue(accountDetail.isFieldLimitReached, 'Account has more than three fields.');
            Assert.areEqual(6, accountDetail.suggestedMaxFields, 'The next limit is double.');
            Assert.isFalse(missingDetail.isFieldLimitReached, 'An object with no fields did not fail for the limit.');
            Assert.isNull(largestDetail.suggestedMaxFields, 'The largest limit has no next one.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Set a limit of two objects and add Account, then prepare the refusals
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.MaxPIIRegistryObjects__c = 2;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { upsert settings; }
            AIAssistSettingsService.cachedSettings = null;
            List<String> refusals = new List<String>();
            AIPiiRegistryDataStructure.RegistryView added;

            // [2] Add Account, add it again, add an object that does not exist, add with a bad limit, add Contact and then a third
            Test.startTest();
                added = AIPiiRegistryEditorService.addRegistryObject(ACCOUNT, 500);

                try {

                    AIPiiRegistryEditorService.addRegistryObject('account', 100);
                } catch (AIPiiRegistryEditorService.AIPiiRegistryEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIPiiRegistryEditorService.addRegistryObject('No_Such_Object__c', 100);
                } catch (AIPiiRegistryEditorService.AIPiiRegistryEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                try {

                    AIPiiRegistryEditorService.addRegistryObject(CONTACT, 501);
                } catch (AIPiiRegistryEditorService.AIPiiRegistryEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }

                AIPiiRegistryEditorService.addRegistryObject(CONTACT, null);

                try {

                    AIPiiRegistryEditorService.addRegistryObject('Opportunity', 100);
                } catch (AIPiiRegistryEditorService.AIPiiRegistryEditorServiceException ex) {

                    refusals.add(ex.getMessage());
                }
            Test.stopTest();

            // [3] Read the registries back after the queued syncs ran
            AIPIIRegistry__c accountRegistry = [SELECT Id, Name, SyncStatus__c, IsActive__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE ObjectAPIName__c = :ACCOUNT];
            AIPIIRegistry__c contactRegistry = [SELECT MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE ObjectAPIName__c = :CONTACT];
            Integer fieldCount = [SELECT COUNT() FROM AIPIIFieldMetadata__c WHERE PIIRegistry__r.ObjectAPIName__c = :ACCOUNT];

            // [4] Check what was saved and what was refused
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED, added.syncStatus, 'The view says queued.');
            Assert.areEqual(ACCOUNT, accountRegistry.Name, 'The name is the API name.');
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED, accountRegistry.SyncStatus__c, 'The queued sync ran.');
            Assert.isTrue(accountRegistry.IsActive__c, 'It is switched on.');
            Assert.isTrue(fieldCount > 0, 'The sync saved its fields.');
            Assert.areEqual(AIAssistApplicationConstants.DEFAULT_PII_FIELDS_TO_QUERY_NEW_OBJECT, contactRegistry.MaxFieldsToQuery__c, 'A blank limit takes the default for a new object.');
            Assert.areEqual(4, refusals.size(), 'Four additions were refused.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Object_Exists, refusals[0], 'A duplicate is refused whatever its case.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Object_Invalid, refusals[1], 'An object that does not exist is refused.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Max_Fields_Invalid, refusals[2], 'A limit over 500 is refused.');
            Assert.areEqual(String.format(Label.AI_PiiRegistry_Error_Limit_Reached, new List<String>{'2'}), refusals[3], 'A full registry is refused.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Account as Failed, and Contact as Queued
            AIPIIRegistry__c failedRegistry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            failedRegistry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
            failedRegistry.MaxFieldsToQuery__c = 3;
            AIPIIRegistry__c queuedRegistry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, false)[0];
            queuedRegistry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED;
            insert new List<AIPIIRegistry__c>{ failedRegistry, queuedRegistry };
            String refusal;

            // [2] Switch Account off and on, sync it with a larger limit, and sync the queued one
            Test.startTest();
                AIPiiRegistryDataStructure.RegistryView switchedOff = AIPiiRegistryEditorService.setRegistryActive(failedRegistry.Id, false);
                AIPiiRegistryDataStructure.RegistryView switchedOn = AIPiiRegistryEditorService.setRegistryActive(failedRegistry.Id, true);
                AIPiiRegistryDataStructure.RegistryView synced = AIPiiRegistryEditorService.syncRegistry(failedRegistry.Id, 500);

                try {

                    AIPiiRegistryEditorService.syncRegistry(queuedRegistry.Id, null);
                } catch (AIPiiRegistryEditorService.AIPiiRegistryEditorServiceException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Read Account back after the queued sync ran
            AIPIIRegistry__c after = [SELECT SyncStatus__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE Id = :failedRegistry.Id];

            // [4] Check the switch, the sync and the refusal
            Assert.isFalse(switchedOff.isActive, 'It was switched off.');
            Assert.isTrue(switchedOn.isActive, 'And on again.');
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED, synced.syncStatus, 'The sync was queued.');
            Assert.areEqual(500, after.MaxFieldsToQuery__c, 'The limit was raised.');
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED, after.SyncStatus__c, 'The sync ran and the limit now covers Account.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Sync_Running, refusal, 'A queued object is not synced twice.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Contact with a plain field and a PII field, and offer two types
            AIPiiRegistryEditorService.typeOptionsForTest = new List<AIPiiRegistryDataStructure.TypeOption>{
                AIAssistTestDataFactory.createAIPiiTypeOption(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, CONTACT_DETAILS, 'SubstituteFromList'),
                AIAssistTestDataFactory.createAIPiiTypeOption(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, null, 'Redacted')
            };
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, CONTACT, true)[0];
            AIPIIFieldMetadata__c plainField = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'Title', null, true)[0];
            AIPIIFieldMetadata__c piiField = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, CONTACT, 'Email', AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, true)[0];
            String refusal;

            // [2] Turn the plain field on as Email, turn the PII field off, turn it on with no type, and ask for a type that is not offered
            Test.startTest();
                AIPiiRegistryDataStructure.FieldView turnedOn = AIPiiRegistryEditorService.saveFieldOverride(plainField.Id, true, AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL);
                AIPiiRegistryDataStructure.FieldView turnedOff = AIPiiRegistryEditorService.saveFieldOverride(piiField.Id, false, null);
                AIPiiRegistryDataStructure.FieldView noType = AIPiiRegistryEditorService.saveFieldOverride(piiField.Id, true, null);

                try {

                    AIPiiRegistryEditorService.saveFieldOverride(plainField.Id, true, 'Not a type');
                } catch (AIPiiRegistryEditorService.AIPiiRegistryEditorServiceException ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Read the plain field back
            AIPIIFieldMetadata__c saved = [SELECT IsPII__c, PIIFieldType__c, ComplianceGroup__c, IsOverridden__c FROM AIPIIFieldMetadata__c WHERE Id = :plainField.Id];

            // [4] Check each override
            Assert.isTrue(turnedOn.isPii, 'The plain field is now PII.');
            Assert.areEqual(CONTACT_DETAILS, turnedOn.complianceGroup, 'It takes the type\'s group.');
            Assert.isTrue(turnedOn.isOverridden, 'And is overridden.');
            Assert.isFalse(turnedOff.isPii, 'The PII field is now plain.');
            Assert.isNull(turnedOff.piiFieldType, 'With no type.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER, noType.piiFieldType, 'A blank type becomes Other.');
            Assert.areEqual(Label.AI_PiiRegistry_Error_Type_Invalid, refusal, 'A type that is not offered is refused.');
            Assert.isTrue(saved.IsPII__c && saved.IsOverridden__c, 'The override was saved.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL, saved.PIIFieldType__c, 'With its type.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register Account with its Name field overridden to PII
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, true)[0];
            AIPIIFieldMetadata__c field = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, ACCOUNT, 'Name', AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, false)[0];
            field.IsOverridden__c = true;
            insert field;

            // [2] Reset it
            Test.startTest();
                AIPiiRegistryDataStructure.FieldView reset = AIPiiRegistryEditorService.resetFieldOverride(field.Id);
            Test.stopTest();

            // [3] Check it is automatic again, and Account Name has no Data Classification
            Assert.isFalse(reset.isOverridden, 'It is no longer overridden.');
            Assert.isFalse(reset.isPii, 'Account Name has no Data Classification, so it is not PII.');
            Assert.isNull(reset.piiFieldType, 'And has no type.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set, and a registry
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, true)[0];
            List<String> refusals = new List<String>();

            // [2] Call four methods as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIPiiRegistryEditorService.getRegistryPage();
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIPiiRegistryEditorService.getRegistryDetail(registry.Id);
                    } catch (AIAssistSettingsEditorService.AIAssistSettingsEditorServiceException ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(2, refusals.size(), 'Both calls were refused.');
            Assert.areEqual(Label.AI_Settings_Error_Access, refusals[0], 'The access label is shown.');
            Assert.areEqual(Label.AI_Settings_Error_Access, refusals[1], 'For each call.');
        }
    }
}
