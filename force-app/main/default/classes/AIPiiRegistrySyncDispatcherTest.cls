/*
Class Name: AIPiiRegistrySyncDispatcherTest

=================================================================
=================================================================

Description: Testing utility for AIPiiRegistrySyncDispatcher: which registries are due, the cap per run, and that nothing happens while the application is off.

=================================================================
=================================================================
Applicable Classes:

AIPiiRegistrySyncDispatcher

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIPiiRegistrySyncDispatcherTest {
  // testScenario1: A never-synced registry is marked Queued and handed to the worker, which syncs it.
  // testScenario2: A registry synced and not past its reset date, an inactive one, and one already queued are not dispatched.
  // testScenario3: A failed registry, and one past its reset date, are dispatched again.
  // testScenario4: The number dispatched is capped by the setting, and never by more than the worker can finish.
  // testScenario5: Bulk: 200 due registries dispatch only the per-run maximum.
  // testScenario6: Switched off, nothing is dispatched.

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
    registry.IsActive__c = true;
    registry.MaxFieldsToQuery__c = 5;
    insert registry;
    Integer dispatched;

    Test.startTest();
    dispatched = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    Test.stopTest();

    Assert.areEqual(1, dispatched, 'One handed over.');
    Assert.areEqual(
      AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED,
      [SELECT SyncStatus__c FROM AIPIIRegistry__c WHERE Id = :registry.Id]
      .SyncStatus__c,
      'The worker ran and synced it.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      3,
      'Account',
      false
    );
    registries[0].IsActive__c = true;
    registries[0].LastSynced__c = System.now().addDays(-1);
    registries[0]
      .SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
    registries[1].IsActive__c = false;
    registries[2].IsActive__c = true;
    registries[2]
      .SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED;
    insert registries;
    Integer dispatched;

    Test.startTest();
    dispatched = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    Test.stopTest();

    Assert.areEqual(0, dispatched, 'None is due.');
  }

  @IsTest
  static void testScenario3() {
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      2,
      'Account',
      false
    );
    for (AIPIIRegistry__c registry : registries) {
      registry.IsActive__c = true;
      registry.MaxFieldsToQuery__c = 3;
      registry.LastSynced__c = System.now().addDays(-3);
    }
    registries[0]
      .SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
    registries[1]
      .SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
    registries[1].CacheResetDate__c = Datetime.now().dateGmt();
    insert registries;
    Integer dispatched;

    Test.startTest();
    dispatched = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    Test.stopTest();

    Assert.areEqual(2, dispatched, 'Both are due.');
  }

  @IsTest
  static void testScenario4() {
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.MaxPIIRegistryObjects__c = 2;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      5,
      'Account',
      false
    );
    for (AIPIIRegistry__c registry : registries) {
      registry.IsActive__c = true;
      registry.MaxFieldsToQuery__c = 1;
    }
    insert registries;
    Integer capped;
    Integer atWorkerLimit;

    Test.startTest();
    capped = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    settings.MaxPIIRegistryObjects__c = 500;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    atWorkerLimit = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    Test.stopTest();

    Assert.areEqual(2, capped, 'The setting.');
    Assert.areEqual(
      3,
      atWorkerLimit,
      'The remaining three, which is under the worker limit.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIPiiFieldTypeClassifier.fieldTypes = new List<AIPiiFieldType__mdt>();
    AIPiiFieldTypeClassifier.complianceGroupsById = new Map<Id, AIPiiComplianceGroup__mdt>();
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.MaxPIIRegistryObjects__c = 999;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    List<AIPIIRegistry__c> registries = AIAssistTestDataFactory.createAIPIIRegistries(
      200,
      'Account',
      false
    );
    for (AIPIIRegistry__c registry : registries) {
      registry.IsActive__c = true;
      registry.MaxFieldsToQuery__c = 1;
    }
    insert registries;
    Integer dispatched;

    Test.startTest();
    dispatched = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN,
      dispatched,
      'The maximum per run.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIPIIRegistry__c registry = AIAssistTestDataFactory.createAIPIIRegistries(
      1,
      'Account',
      false
    )[0];
    registry.IsActive__c = true;
    insert registry;
    Integer dispatched;

    Test.startTest();
    dispatched = AIPiiRegistrySyncDispatcher.dispatchDueRegistries();
    Test.stopTest();

    Assert.areEqual(0, dispatched, 'Nothing while off.');
  }
}
