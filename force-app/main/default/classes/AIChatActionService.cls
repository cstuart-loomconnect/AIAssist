/*
Class Name: AIChatActionService

=================================================================
=================================================================

Description: The Suggested Action card on an AI reply, and running it when the user clicks it.

Only the action actually suggested on the reply can run, and only for a user the dispatcher allows:
AIWorkflowActionDispatcher does the gating (plan, the user's own setting, assignment to the agent,
confirmation) and records the evidence. This class passes on whether the user confirmed and turns the
result into a message the window can show. A refusal or failure comes back as a result with its Custom
Label, never with class or flow names.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from the old action service. Runs through AIWorkflowActionDispatcher, which records the evidence, so no step is written here.
*/

public with sharing class AIChatActionService {
  public class AIChatActionServiceException extends Exception {
  }

  // Runs the action suggested on reply. isConfirmed is whether the user pressed the confirmation.
  public static AIChatDataStructure.ActionResult runSuggestedAction(
    AIConversationMessage__c reply,
    String inputsJson,
    Boolean isConfirmed
  ) {
    AIChatDataStructure.ActionResult result = new AIChatDataStructure.ActionResult();

    if (reply.SuggestedWorkflowAction__c == null)
      throw new AIChatActionServiceException(
        Label.AI_Error_Action_Not_Permitted
      );

    Map<String, Object> inputs = String.isBlank(inputsJson)
      ? new Map<String, Object>()
      : (Map<String, Object>) JSON.deserializeUntyped(inputsJson);

    try {
      Object output = AIWorkflowActionDispatcher.runWorkflowAction(
        reply.SuggestedWorkflowAction__c,
        reply.AIConversation__r.AIAgent__c,
        reply.Id,
        AIChatDataStructure.toIdOrNull(
          reply.AIConversation__r.RelatedRecordId__c
        ),
        inputs,
        isConfirmed
      );
      result.isSuccess = true;
      result.message = output instanceof String &&
        String.isNotBlank((String) output)
        ? (String) output
        : null;
    } catch (Exception refusal) {
      if (refusal.getTypeName().startsWith('System.')) {
        throw refusal;
      }
      result.message = refusal.getMessage();
    }

    return result;
  }

  public static AIChatDataStructure.SuggestedAction toSuggestedAction(
    AIWorkflowAction__c action
  ) {
    AIChatDataStructure.SuggestedAction suggestedActionCard = new AIChatDataStructure.SuggestedAction();
    suggestedActionCard.id = action.Id;
    suggestedActionCard.name = action.ActionName__c;
    suggestedActionCard.description = action.Description__c;
    suggestedActionCard.requiresConfirmation =
      action.RequiresConfirmation__c == true;
    suggestedActionCard.confirmationMessage = String.isBlank(
        action.ConfirmationMessage__c
      )
      ? Label.AI_Chat_Confirm_Action_Default
      : action.ConfirmationMessage__c;
    suggestedActionCard.inputFields = parseInputSchema(action.InputSchema__c);

    return suggestedActionCard;
  }

  // InputSchema__c is a JSON Schema object; each property becomes one field on "Edit first". A malformed schema means no editable fields.
  @TestVisible
  private static List<AIChatDataStructure.ActionInputField> parseInputSchema(
    String inputSchema
  ) {
    List<AIChatDataStructure.ActionInputField> fields = new List<AIChatDataStructure.ActionInputField>();

    if (String.isBlank(inputSchema))
      return fields;

    try {
      Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(
        inputSchema
      );
      Map<String, Object> properties = (Map<String, Object>) schema.get(
        'properties'
      );
      if (properties == null)
        return fields;

      Set<String> requiredNames = new Set<String>();
      if (schema.get('required') instanceof List<Object>) {
        for (Object requiredName : (List<Object>) schema.get('required'))
          requiredNames.add(String.valueOf(requiredName));
      }

      for (String propertyName : properties.keySet()) {
        Map<String, Object> property = (Map<String, Object>) properties.get(
          propertyName
        );
        String jsonType = property.get('type') == null
          ? 'string'
          : String.valueOf(property.get('type'));
        String format = property.get('format') == null
          ? null
          : String.valueOf(property.get('format'));

        AIChatDataStructure.ActionInputField field = new AIChatDataStructure.ActionInputField();
        field.name = propertyName;
        field.label = property.get('title') == null
          ? AIChatDataStructure.humanise(propertyName)
          : String.valueOf(property.get('title'));
        field.helpText = property.get('description') == null
          ? null
          : String.valueOf(property.get('description'));
        field.required = requiredNames.contains(propertyName);
        field.inputType = jsonType == 'integer' ||
          jsonType == 'number'
          ? 'number'
          : jsonType == 'boolean'
              ? 'checkbox'
              : format == 'date'
                  ? 'date'
                  : format == 'date-time'
                      ? 'datetime'
                      : property.get('maxLength') != null &&
                          Integer.valueOf(property.get('maxLength')) > 255
                          ? 'textarea'
                          : 'text';

        fields.add(field);
      }
    } catch (Exception malformedSchema) {
      return new List<AIChatDataStructure.ActionInputField>();
    }

    return fields;
  }
}
