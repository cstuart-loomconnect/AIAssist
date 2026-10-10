/*
Script Name: 01-settings.apex

=================================================================
=================================================================

Description: Custom settings: the organisation rows of AIAssistSettings__c and AIAssistUISettings__c,
and a profile and a user row of AIAssistUISettings__c for the running user.

Safe to run again: the rows are overwritten with the values here.

Part of the sample data set: run scripts/load-sample-data.sh <org alias> to load all five parts in
order, or this part alone with sf apex run --file.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class SampleDataLoader {
  // =============================================================
  // Options
  // =============================================================

  Boolean isProductionAllowed = false; // The script refuses to run outside a sandbox or scratch org unless this is set.
  Boolean shouldEnableApplication = true; // Switches AI Assist on in this org. Nothing calls a provider until a model configuration is active.

  // =============================================================

  final String PREFIX = 'Sample - ';
  List<String> summary = new List<String>();
  List<String> problems = new List<String>();
  Id runningUserId = UserInfo.getUserId();

  public void run() {
    if (
      !isProductionAllowed &&
      ![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox
    )
      problems.add('Not a sandbox or scratch org. Nothing was loaded.');
    else
      load();

    System.debug(
      LoggingLevel.ERROR,
      'SAMPLE DATA: 01-settings.apex\n  ' +
        String.join(summary, '\n  ') +
        (problems.isEmpty()
          ? '\nNo problems.'
          : '\nPROBLEMS (' +
            problems.size() +
            ')\n  ' +
            String.join(problems, '\n  '))
    );
  }

  void load() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    if (settings == null || settings.Id == null) {
      settings = (AIAssistSettings__c) AIAssistSettings__c.SObjectType.newSObject(
        null,
        true
      );
      settings.SetupOwnerId = UserInfo.getOrganizationId();
    }
    settings.IsEnabled__c = shouldEnableApplication;
    settings.AIUsagePolicyUrl__c = 'https://example.com/ai-usage-policy';
    settings.CurrentTermsVersion__c = '1.0';
    settings.StepCaptureMode__c = 'Full';
    settings.MaxMessageLength__c = 4000;
    settings.MaxMessagesPerUserPerMinute__c = 10;
    settings.MaxMessagesInFlight__c = 20;
    settings.MaxPIIRegistryObjects__c = 10;

    // Each row starts from the field defaults: a checkbox is never blank, so a profile or user row built empty would switch the default-on settings off.
    AIAssistUISettings__c organisationUi = uiSettingsFor(
      UserInfo.getOrganizationId()
    );
    organisationUi.MaxVisibleMessageHistory__c = 50;
    organisationUi.SuggestedActionsDisplay__c = 'Cards';
    organisationUi.ShowTimestampOnMessages__c = true;
    organisationUi.AllowInlineWorkflowActions__c = true;

    AIAssistUISettings__c profileUi = uiSettingsFor(UserInfo.getProfileId());
    profileUi.MaxVisibleMessageHistory__c = 75;
    profileUi.SuggestedActionsDisplay__c = 'Cards';
    profileUi.ShowTimestampOnMessages__c = true;
    profileUi.AllowInlineWorkflowActions__c = true;
    profileUi.ShowExecutionTraceToUser__c = true;

    AIAssistUISettings__c userUi = uiSettingsFor(runningUserId);
    userUi.MaxVisibleMessageHistory__c = 100;
    userUi.SuggestedActionsDisplay__c = 'Inline Buttons';
    userUi.ShowTimestampOnMessages__c = true;
    userUi.AllowInlineWorkflowActions__c = true;
    userUi.ShowExecutionTraceToUser__c = true;

    try {
      upsert settings;
      upsert new List<AIAssistUISettings__c>{
        organisationUi,
        profileUi,
        userUi
      };
      summary.add(
        'Custom settings: AIAssistSettings__c (organisation), AIAssistUISettings__c (organisation, profile, user)'
      );
    } catch (Exception caughtException) {
      problems.add('Custom settings: ' + caughtException.getMessage());
    }
  }

  AIAssistUISettings__c uiSettingsFor(Id setupOwnerId) {
    List<AIAssistUISettings__c> existing = [
      SELECT Id
      FROM AIAssistUISettings__c
      WHERE SetupOwnerId = :setupOwnerId
      LIMIT 1
    ];
    AIAssistUISettings__c uiSettings = (AIAssistUISettings__c) AIAssistUISettings__c.SObjectType.newSObject(
      null,
      true
    );
    if (existing.isEmpty())
      uiSettings.SetupOwnerId = setupOwnerId;
    else
      uiSettings.Id = existing[0].Id;
    return uiSettings;
  }
}

new SampleDataLoader().run();
