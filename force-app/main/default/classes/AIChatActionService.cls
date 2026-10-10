/*
Class Name: AIChatActionService

=================================================================
=================================================================

Description: Builds the Suggested Action card on an AI reply, and runs the action when the user clicks it.

Step 1: Build the card from the suggested workflow action, with its editable input fields
Step 2: Check the reply has a suggested action, otherwise refuse
Step 3: Pass the user's inputs and confirmation to AIWorkflowActionDispatcher, which does the gating
Step 4: Return the result message, or the refusal message, for the window to show

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIChatActionService {
  public class AIChatActionServiceException extends Exception {
  }

  // Runs the action suggested on the reply. isConfirmed is whether the user pressed the confirmation.
  public static AIChatDataStructure.ActionResult runSuggestedAction(
    AIConversationMessage__c reply,
    String inputsJson,
    Boolean isConfirmed
  ) {
    // [1] Start with an empty result
    AIChatDataStructure.ActionResult result = new AIChatDataStructure.ActionResult();

    // [2] Stop if the reply has no suggested action, because only a suggested action can run
    if (reply.SuggestedWorkflowAction__c == null)
      throw new AIChatActionServiceException(
        Label.AI_Error_Action_Not_Permitted
      );

    // [3] Read the inputs the user entered, or use none if there are none
    Map<String, Object> inputs = String.isBlank(inputsJson)
      ? new Map<String, Object>()
      : (Map<String, Object>) JSON.deserializeUntyped(inputsJson);

    try {
      // [4] Run the action through the dispatcher, which decides whether this user may run it
      Object output = AIWorkflowActionDispatcher.runWorkflowAction(
        reply.SuggestedWorkflowAction__c,
        reply.AIConversation__r.AIAgent__c,
        reply.Id,
        AIChatDataStructure.getIdOrNull(
          reply.AIConversation__r.RelatedRecordId__c
        ),
        inputs,
        isConfirmed
      );

      // [5] Record the success and any text the action returned
      result.isSuccess = true;
      result.message = output instanceof String &&
        String.isNotBlank((String) output)
        ? (String) output
        : null;
    } catch (Exception ex) {
      // [6] Pass on system errors, but show a refusal to the user as the result message
      if (ex.getTypeName().startsWith('System.'))
        throw ex;
      result.message = ex.getMessage();
    }

    // [7] Return the result
    return result;
  }

  // Builds the card the window shows for a suggested action.
  public static AIChatDataStructure.SuggestedAction buildSuggestionAction(
    AIWorkflowAction__c action
  ) {
    // [1] Copy the action's details onto the card
    AIChatDataStructure.SuggestedAction suggestedActionCard = new AIChatDataStructure.SuggestedAction();
    suggestedActionCard.id = action.Id;
    suggestedActionCard.name = action.ActionName__c;
    suggestedActionCard.description = action.Description__c;
    suggestedActionCard.requiresConfirmation =
      action.RequiresConfirmation__c == true;

    // [2] Use the default confirmation message when the action has none
    suggestedActionCard.confirmationMessage = String.isBlank(
        action.ConfirmationMessage__c
      )
      ? Label.AI_Chat_Confirm_Action_Default
      : action.ConfirmationMessage__c;

    // [3] Add the fields the user can edit before running the action
    suggestedActionCard.inputFields = buildInputFields(action.InputSchema__c);

    // [4] Return the card
    return suggestedActionCard;
  }

  // InputSchema__c is a JSON Schema object; each property becomes one field on "Edit first". A malformed schema means no editable fields.
  @TestVisible
  private static List<AIChatDataStructure.ActionInputField> buildInputFields(
    String inputSchema
  ) {
    // [1] Start with no fields
    List<AIChatDataStructure.ActionInputField> fields = new List<AIChatDataStructure.ActionInputField>();

    // [2] Nothing to read when there is no schema
    if (String.isBlank(inputSchema))
      return fields;

    try {
      // [3] Read the schema and find its properties
      Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(
        inputSchema
      );
      Map<String, Object> properties = (Map<String, Object>) schema.get(
        'properties'
      );

      if (properties == null)
        return fields;

      // [4] Collect the names of the required properties
      Set<String> requiredNames = new Set<String>();

      if (schema.get('required') instanceof List<Object>) {
        for (Object requiredName : (List<Object>) schema.get('required'))
          requiredNames.add(String.valueOf(requiredName));
      }

      // [5] Turn each property into one input field
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
    } catch (Exception ex) {
      // [6] Offer no editable fields when the schema is malformed
      return new List<AIChatDataStructure.ActionInputField>();
    }

    // [7] Return the fields
    return fields;
  }
}
