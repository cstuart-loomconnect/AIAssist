/*
Class Name: AIPiiRegistrySyncWorkerTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistrySyncWorker: the field metadata it saves for a registry, with no callout.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistrySyncWorker: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPiiRegistrySyncWorkerTest {

    // testScenario1: A registry whose limit covers the object saves its fields keyed by object and field, with label, type and PII flag, and is Synced.
    // testScenario2: Running again updates the same rows instead of adding more.
    // testScenario3: An object with no fields to read is still marked Synced, with no rows.
    // testScenario4: Several registries are processed by one job, and no ids, or ids that are not registries, do nothing.
    // testScenario5: As a queued job it runs with no callout.
    // testScenario6: An object with more fields than the limit has its first fields saved, is marked Failed with a time, and the reason is logged once.
    // testScenario7: A field an administrator overrode keeps its PII choice through a sync, while its label and type are refreshed.

    private static final String ACCOUNT = 'Account';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a registry for Account with a reset date set
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            registry.MaxFieldsToQuery__c = 500;
            registry.CacheResetDate__c = Datetime.now().dateGmt().addDays(-1);
            insert registry;

            // [2] Run the worker for the registry
            Test.startTest();
                new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
            Test.stopTest();

            // [3] Read the saved fields and the registry back
            List<AIPIIFieldMetadata__c> fields = [SELECT FieldKey__c, FieldAPIName__c, FieldLabel__c, DataType__c, IsPII__c FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registry.Id];
            AIPIIRegistry__c synced = [SELECT SyncStatus__c, LastSynced__c, CacheResetDate__c FROM AIPIIRegistry__c WHERE Id = :registry.Id];

            // [4] Check the fields, their keys and the Synced registry
            Assert.isTrue(fields.size() >= 5, 'The fields of the object are saved.');
            Assert.areEqual('Account.' + fields[0].FieldAPIName__c, fields[0].FieldKey__c, 'Keyed by object and field.');
            Assert.isNotNull(fields[0].DataType__c, 'The type is saved.');

            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED, synced.SyncStatus__c, 'Synced.');
            Assert.isNotNull(synced.LastSynced__c, 'With a time.');
            Assert.isNull(synced.CacheResetDate__c, 'The reset date is cleared so it does not retrigger.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a registry for Account
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            registry.MaxFieldsToQuery__c = 4;
            insert registry;

            // [2] Run the worker twice for the same registry
            Test.startTest();
                new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
                new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
            Test.stopTest();

            // [3] Count the saved fields
            Integer fieldCount = [SELECT COUNT() FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registry.Id];

            // [4] Check the second run updated rather than added rows
            Assert.areEqual(4, fieldCount, 'Matched on the field key.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a registry for an object that does not exist
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, 'No_Such_Object__c', true)[0];

            // [2] Run the worker for the registry
            Test.startTest();
                new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
            Test.stopTest();

            // [3] Read the field count and sync status back
            Integer fieldCount = [SELECT COUNT() FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registry.Id];
            String syncStatus = [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id].SyncStatus__c;

            // [4] Check there are no fields and the registry is still Synced
            Assert.areEqual(0, fieldCount, 'No fields.');
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED, syncStatus, 'Nothing failed.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create registries for Account and Contact
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

            List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(2, ACCOUNT, false);

            for (AIPIIRegistry__c registry : registries) registry.MaxFieldsToQuery__c = 2;

            registries[1].ObjectAPIName__c = 'Contact';
            insert registries;

            // [2] Run the worker with no ids, a non-registry id and both registry ids
            Test.startTest();
                new AIPiiRegistrySyncWorker(null).execute(null);
                new AIPiiRegistrySyncWorker(new List<Id>{ UserInfo.getUserId() }).execute(null);
                new AIPiiRegistrySyncWorker(new List<Id>{ registries[0].Id, registries[1].Id }).execute(null);
            Test.stopTest();

            // [3] Read the field count and synced count back
            Integer fieldCount = [SELECT COUNT() FROM AIPIIFieldMetadata__c];
            Integer failedCount = [SELECT COUNT() FROM AIPIIRegistry__c WHERE SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED];

            // [4] Check both registries were processed and the bad input did nothing
            Assert.areEqual(4, fieldCount, 'Two fields for each of two objects.');
            Assert.areEqual(2, failedCount, 'Both have more than two fields, so both are Failed.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a registry for Account
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            registry.MaxFieldsToQuery__c = 2;
            insert registry;

            // [2] Enqueue the worker as a queued job
            Test.startTest();
                System.enqueueJob(new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }));
            Test.stopTest();

            // [3] Read the registry back
            String syncStatus = [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id].SyncStatus__c;

            // [4] Check the job synced the registry without a callout mock
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED, syncStatus, 'The job finished its work without a callout mock; Account has more than two fields.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a registry for Account that reads only three fields
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            registry.MaxFieldsToQuery__c = 3;
            insert registry;

            // [2] Run the worker for the registry
            Test.startTest();
                new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
            Test.stopTest();

            // [3] Read the fields, the registry and the platform log back
            Integer fieldCount = [SELECT COUNT() FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registry.Id];
            AIPIIRegistry__c failed = [SELECT SyncStatus__c, LastSynced__c FROM AIPIIRegistry__c WHERE Id = :registry.Id];
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the first fields were kept, the registry Failed with a time, and the reason was logged
            Assert.areEqual(3, fieldCount, 'Only the first three fields are saved.');
            Assert.areEqual(AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED, failed.SyncStatus__c, 'The rest of the fields were never checked, so the sync failed.');
            Assert.isNotNull(failed.LastSynced__c, 'The failed sync has a time.');
            Assert.areEqual(1, logs.size(), 'One log row says why.');
            Assert.areEqual('AIPiiRegistrySyncWorker', logs[0].ClassName__c, 'The worker logged it.');
            Assert.areEqual('execute', logs[0].MethodName__c, 'From execute.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a registry for Account with a field an administrator overrode to PII, and one left automatic
            AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
            AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

            AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(1, ACCOUNT, false)[0];
            registry.MaxFieldsToQuery__c = 500;
            insert registry;

            AIPIIFieldMetadata__c overridden = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, ACCOUNT, 'Name', AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, false)[0];
            overridden.IsOverridden__c = true;
            overridden.FieldLabel__c = 'Old label';
            overridden.ComplianceGroup__c = 'Chosen group';
            AIPIIFieldMetadata__c automatic = AIAssistTestDataFactory.createAIPIIFieldMetadata(registry.Id, ACCOUNT, 'Phone', AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE, false)[0];
            insert new List<AIPIIFieldMetadata__c>{ overridden, automatic };

            // [2] Run the worker for the registry
            Test.startTest();
                new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
            Test.stopTest();

            // [3] Read the two fields back
            AIPIIFieldMetadata__c overriddenAfter = [SELECT FieldLabel__c, IsPII__c, PIIFieldType__c, ComplianceGroup__c, IsOverridden__c FROM AIPIIFieldMetadata__c WHERE Id = :overridden.Id];
            AIPIIFieldMetadata__c automaticAfter = [SELECT IsPII__c, PIIFieldType__c FROM AIPIIFieldMetadata__c WHERE Id = :automatic.Id];

            // [4] Check the choice survived on the overridden field and the automatic one was classified again
            Assert.isTrue(overriddenAfter.IsPII__c, 'The overridden field is still PII.');
            Assert.areEqual(AIAssistApplicationConstants.PII_FIELD_TYPE_NAME, overriddenAfter.PIIFieldType__c, 'Its type is kept.');
            Assert.areEqual('Chosen group', overriddenAfter.ComplianceGroup__c, 'Its group is kept.');
            Assert.isTrue(overriddenAfter.IsOverridden__c, 'It stays overridden.');
            Assert.areNotEqual('Old label', overriddenAfter.FieldLabel__c, 'Its label is refreshed.');
            Assert.isFalse(automaticAfter.IsPII__c, 'The automatic field is classified again, and Phone has no Data Classification.');
            Assert.isNull(automaticAfter.PIIFieldType__c, 'So it has no type.');
        }
    }
}
