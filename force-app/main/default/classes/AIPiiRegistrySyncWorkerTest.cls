/*
Class Name: AIPiiRegistrySyncWorkerTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistrySyncWorker: the field metadata it saves for a registry, with no callout.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistrySyncWorker

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
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Account',
      false
    )[0];
    registry.MaxFieldsToQuery__c = 5;
    registry.CacheResetDate__c = Datetime.now().dateGmt().addDays(-1);
    insert registry;

    Test.startTest();
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    Test.stopTest();

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
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Account',
      false
    )[0];
    registry.MaxFieldsToQuery__c = 4;
    insert registry;

    Test.startTest();
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    Test.stopTest();

    Assert.areEqual(
      4,
      [
        SELECT COUNT()
        FROM AIPIIFieldMetadata__c
        WHERE PIIRegistry__c = :registry.Id
      ],
      'Matched on the field key.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'No_Such_Object__c',
      true
    )[0];

    Test.startTest();
    new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }).execute(null);
    Test.stopTest();

    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AIPIIFieldMetadata__c
        WHERE PIIRegistry__c = :registry.Id
      ],
      'No fields.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
      [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id]
      .SyncStatus__c,
      'Nothing failed.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      2,
      'Account',
      false
    );
    for (AIPIIRegistry__c registry : registries)
      registry.MaxFieldsToQuery__c = 2;
    registries[1].ObjectAPIName__c = 'Contact';
    insert registries;

    Test.startTest();
    new AIPiiRegistrySyncWorker(null).execute(null);
    new AIPiiRegistrySyncWorker(new List<Id>{ UserInfo.getUserId() })
      .execute(null);
    new AIPiiRegistrySyncWorker(
        new List<Id>{ registries[0].Id, registries[1].Id }
      )
      .execute(null);
    Test.stopTest();

    Assert.areEqual(
      4,
      [SELECT COUNT() FROM AIPIIFieldMetadata__c],
      'Two fields for each of two objects.'
    );
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIPIIRegistry__c
        WHERE
          SyncStatus__c = :AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED
      ],
      'Both Synced.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Account',
      false
    )[0];
    registry.MaxFieldsToQuery__c = 2;
    insert registry;

    Test.startTest();
    System.enqueueJob(new AIPiiRegistrySyncWorker(new List<Id>{ registry.Id }));
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
      [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id]
      .SyncStatus__c,
      'No callout mock was needed.'
    );
  }
}
