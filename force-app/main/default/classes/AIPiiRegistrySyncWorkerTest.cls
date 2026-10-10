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

@IsTest
private class AIPiiRegistrySyncWorkerTest {
  // testScenario1: A registry's fields are saved keyed by object and field, with label, type and PII flag, and the registry is Synced.
  // testScenario2: Running again updates the same rows instead of adding more.
  // testScenario3: An object with no fields to read is still marked Synced, with no rows.
  // testScenario4: Several registries are synced by one job, and no ids, or ids that are not registries, do nothing.
  // testScenario5: As a queued job it runs with no callout.

  private static final String ACCOUNT = 'Account';

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
    // [1] Create a registry for Account with a reset date set
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      ACCOUNT,
      false
    )[0];
    registry.MaxFieldsToQuery__c = 5;
    registry.CacheResetDate__c = Datetime.now().dateGmt().addDays(-1);
    insert registry;

    // [2] Run the worker for the registry
    Test.startTest();
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    Test.stopTest();

    // [3] Read the saved fields and the registry back
    List<AIPIIFieldMetadata__c> fields = [
      SELECT FieldKey__c, FieldAPIName__c, FieldLabel__c, DataType__c, IsPII__c
      FROM AIPIIFieldMetadata__c
      WHERE PIIRegistry__c = :registry.Id
    ];
    AIPIIRegistry__c synced = [
      SELECT SyncStatus__c, LastSynced__c, CacheResetDate__c
      FROM AIPIIRegistry__c
      WHERE Id = :registry.Id
    ];

    // [4] Check the fields, their keys and the Synced registry
    Assert.areEqual(5, fields.size(), 'Bounded by the registry\'s maximum.');
    Assert.areEqual(
      'Account.' + fields[0].FieldAPIName__c,
      fields[0].FieldKey__c,
      'Keyed by object and field.'
    );
    Assert.isNotNull(fields[0].DataType__c, 'The type is saved.');

    Assert.areEqual(
      AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
      synced.SyncStatus__c,
      'Synced.'
    );
    Assert.isNotNull(synced.LastSynced__c, 'With a time.');
    Assert.isNull(
      synced.CacheResetDate__c,
      'The reset date is cleared so it does not retrigger.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create a registry for Account
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      ACCOUNT,
      false
    )[0];
    registry.MaxFieldsToQuery__c = 4;
    insert registry;

    // [2] Run the worker twice for the same registry
    Test.startTest();
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    Test.stopTest();

    // [3] Count the saved fields
    Integer fieldCount = [
      SELECT COUNT()
      FROM AIPIIFieldMetadata__c
      WHERE PIIRegistry__c = :registry.Id
    ];

    // [4] Check the second run updated rather than added rows
    Assert.areEqual(4, fieldCount, 'Matched on the field key.');
  }

  @IsTest
  static void testScenario3() {
    // [1] Create a registry for an object that does not exist
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'No_Such_Object__c',
      true
    )[0];

    // [2] Run the worker for the registry
    Test.startTest();
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    Test.stopTest();

    // [3] Read the field count and sync status back
    Integer fieldCount = [
      SELECT COUNT()
      FROM AIPIIFieldMetadata__c
      WHERE PIIRegistry__c = :registry.Id
    ];
    String syncStatus = [
      SELECT SyncStatus__c
      FROM AIPIIRegistry__c
      WHERE Id = :registry.Id
    ]
    .SyncStatus__c;

    // [4] Check there are no fields and the registry is still Synced
    Assert.areEqual(0, fieldCount, 'No fields.');
    Assert.areEqual(
      AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
      syncStatus,
      'Nothing failed.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create registries for Account and Contact
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      2,
      ACCOUNT,
      false
    );

    for (AIPIIRegistry__c registry : registries)
      registry.MaxFieldsToQuery__c = 2;

    registries[1].ObjectAPIName__c = 'Contact';
    insert registries;

    // [2] Run the worker with no ids, a non-registry id and both registry ids
    Test.startTest();
    new AIPiiRegistrySyncWorker(null).execute(null);
    new AIPiiRegistrySyncWorker(new List<Id>{ UserInfo.getUserId() })
      .execute(null);
    new AIPiiRegistrySyncWorker(
        new List<Id>{ registries[0].Id, registries[1].Id }
      )
      .execute(null);
    Test.stopTest();

    // [3] Read the field count and synced count back
    Integer fieldCount = [SELECT COUNT() FROM AIPIIFieldMetadata__c];
    Integer syncedCount = [
      SELECT COUNT()
      FROM AIPIIRegistry__c
      WHERE SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED
    ];

    // [4] Check both registries were synced and the bad input did nothing
    Assert.areEqual(4, fieldCount, 'Two fields for each of two objects.');
    Assert.areEqual(2, syncedCount, 'Both Synced.');
  }

  @IsTest
  static void testScenario5() {
    // [1] Create a registry for Account
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();

    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      ACCOUNT,
      false
    )[0];
    registry.MaxFieldsToQuery__c = 2;
    insert registry;

    // [2] Enqueue the worker as a queued job
    Test.startTest();
    System.enqueueJob(new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }));
    Test.stopTest();

    // [3] Read the registry back
    String syncStatus = [
      SELECT SyncStatus__c
      FROM AIPIIRegistry__c
      WHERE Id = :registry.Id
    ]
    .SyncStatus__c;

    // [4] Check the job synced the registry without a callout mock
    Assert.areEqual(
      AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
      syncStatus,
      'No callout mock was needed.'
    );
  }
}
