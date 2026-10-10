/*
Class Name: AIPlatformLogEventTrigger

=================================================================
=================================================================

Description: Trigger for AIPlatformLogEvent__e. Runs only on the package's own object, never on a subscriber's.

Step 1: Stop if the application is switched off
Step 2: Route after insert events to the handler, which holds the logic

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

trigger AIPlatformLogEventTrigger on AIPlatformLogEvent__e(after insert) {
  // [1] Do nothing while the application is switched off
  if (!AIAssistSettingsService.isEnabled())
    return;

  // [2] Pass the new events to the handler
  if (Trigger.isAfter && Trigger.isInsert) {
    AIPlatformLogEventHandler.handleAfterInsert(Trigger.new);
  }
}
