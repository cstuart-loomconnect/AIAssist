/*
Class Name: AIPlatformLogEventTrigger

=================================================================
=================================================================

Description: Trigger for AIPlatformLogEvent__e events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIPlatformLogEventTrigger on AIPlatformLogEvent__e(after insert) {
  if (!AIAssistSettingsService.isEnabled())
    return;

  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      AIPlatformLogEventHandler.handleAfterInsert(Trigger.new);
    }
  }

}
