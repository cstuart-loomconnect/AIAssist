/*
Class Name: AIFeatureServiceTest

=================================================================
=================================================================

Description: Testing utility for AIFeatureService: one check for whether a feature may be used, by org, then user, and the org's day.

=================================================================
=================================================================
Applicable Classes:

AIFeatureService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIFeatureServiceTest {
  // testScenario1: An unknown feature is never enabled and is refused as User.
  // testScenario2: The org layer: with the application off, or activated in another org, a feature a user uses is refused as Org.
  // testScenario3: The user layer: the custom permission grants it, so does the user's settings, and with neither it is refused as User. Running actions needs the settings to be active; debug does not.
  // testScenario4: A feature with no permission is granted by the user's settings alone, and the user state the chat window gets comes from the same check.

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
    Test.startTest();
    Boolean unknown = AIFeatureService.isFeatureEnabled('Teleportation');
    String unknownLayer = AIFeatureService.getBlockingLayer(
      'Teleportation',
      new AIUserSettings__c(IsActive__c = true)
    );
    Test.stopTest();

    Assert.isFalse(unknown, 'An unknown feature is never enabled.');
    Assert.areEqual(
      AIFeatureService.LAYER_USER,
      unknownLayer,
      'Refused as User.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      true
    );
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();

    Test.startTest();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.clearCache();
    String debugWhileOff = AIFeatureService.getBlockingLayer(
      AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE,
      null
    );
    settings.IsEnabled__c = true;
    update settings;
    AIAssistSettingsService.clearCache();
    Boolean debugWhileOn = AIFeatureService.isFeatureEnabled(
      AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE
    );
    Test.stopTest();

    Assert.areEqual(AIFeatureService.LAYER_ORG, debugWhileOff, 'Switched off.');
    Assert.isTrue(debugWhileOn, 'On, and the permission is held.');
  }

  @IsTest
  static void testScenario3() {
    String runActions = AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS;
    String debugMode = AIAssistApplicationConstants.APP_FEATURE_DEBUG_MODE;
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      false
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      false
    );

    Test.startTest();
    String withNeither = AIFeatureService.getBlockingLayer(
      runActions,
      new AIUserSettings__c(IsActive__c = true)
    );
    // No settings passed and none in the org for this user: they are looked up.
    String withNoSettingsRow = AIFeatureService.getBlockingLayer(
      runActions,
      null
    );
    Boolean bySettings = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c(
        IsActive__c = true,
        WorkflowActionsEnabled__c = true
      )
    );
    Boolean byInactiveSettings = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c(
        IsActive__c = false,
        WorkflowActionsEnabled__c = true
      )
    );
    Boolean debugByInactiveSettings = AIFeatureService.isFeatureEnabled(
      debugMode,
      new AIUserSettings__c(IsActive__c = false, DebugModeEnabled__c = true)
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      true
    );
    Boolean byPermission = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c()
    );
    AIFeatureService.permissionForTest.clear();
    Boolean realPermissionCheck = AIFeatureService.isFeatureEnabled(
      runActions,
      new AIUserSettings__c(
        IsActive__c = true,
        WorkflowActionsEnabled__c = true
      )
    );
    Test.stopTest();

    Assert.areEqual(AIFeatureService.LAYER_USER, withNeither, 'Not granted.');
    Assert.areEqual(AIFeatureService.LAYER_USER, withNoSettingsRow, 'No row.');
    Assert.isTrue(bySettings, 'The user\'s settings grant it.');
    Assert.isFalse(byInactiveSettings, 'Actions need active settings.');
    Assert.isTrue(debugByInactiveSettings, 'Debug does not.');
    Assert.isTrue(byPermission, 'The custom permission grants it alone.');
    Assert.isTrue(realPermissionCheck, 'With the real permission check too.');
  }

  @IsTest
  static void testScenario4() {
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_DEBUG_MODE,
      true
    );
    AIFeatureService.permissionForTest.put(
      AIAssistApplicationConstants.PERMISSION_RUN_ACTIONS,
      false
    );

    Test.startTest();
    AIChatDataStructure.UserState noSettings = AIChatStateService.buildUserState(
      null
    );
    AIChatDataStructure.UserState withSettings = AIChatStateService.buildUserState(
      new AIUserSettings__c(
        IsActive__c = true,
        WorkflowActionsEnabled__c = true,
        ConversationExportEnabled__c = true
      )
    );
    Test.stopTest();

    Assert.isTrue(noSettings.debugMode, 'The permission, with no settings.');
    Assert.isFalse(noSettings.workflowActionsEnabled, 'Not granted.');
    Assert.isFalse(noSettings.exportEnabled, 'Export has no permission.');
    Assert.isTrue(withSettings.workflowActionsEnabled, 'By the settings.');
    Assert.isTrue(withSettings.exportEnabled, 'By the settings.');
  }
}
