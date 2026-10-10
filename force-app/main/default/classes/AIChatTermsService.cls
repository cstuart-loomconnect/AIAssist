/*
Class Name: AIChatTermsService

=================================================================
=================================================================

Description: Accepting the usage terms.

Step 1: Read the current terms version from the settings
Step 2: Record an acknowledgment of that version, signed with the user's name
Step 3: Log and refuse if it could not be saved

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatTermsService {
  public class AIChatTermsServiceException extends Exception {
  }

  // Records that the user accepted the current terms. Written as the user, in user mode, because the object model only lets users acknowledge for themselves.
  public static void acknowledgeTerms() {
    // [1] Read the current terms version from the settings
    String currentTermsVersion = AIAssistSettingsService.getSettings()
      .CurrentTermsVersion__c;

    // [2] Record the acknowledgment, signed with the user's name
    Database.SaveResult insertResult = Database.insert(
      new AITermsAcknowledgment__c(
        User__c = UserInfo.getUserId(),
        TermsVersion__c = String.isBlank(currentTermsVersion)
          ? null
          : currentTermsVersion.trim(),
        AcknowledgedDate__c = System.now(),
        SignatureText__c = UserInfo.getName().left(120)
      ),
      false,
      AccessLevel.USER_MODE
    );

    // [3] Log and refuse if the save fails
    if (!insertResult.isSuccess()) {
      AIPlatformLogManager.logCustomMessage(
        'Terms could not be acknowledged: ' +
        insertResult.getErrors()[0].getMessage(),
        null,
        'AIChatTermsService',
        'acknowledgeTerms',
        null
      );
      throw new AIChatTermsServiceException(Label.AI_Error_Generic);
    }
  }
}
