/*
Class Name: AIWorkflowActionDispatcher

=================================================================
=================================================================

Description: Runs one Workflow Action a user has chosen to run from a suggestion in the chat. The counterpart of
AIDataSourceDispatcher, with the extra care an action that can change data needs.

In order, and each refusal is an AIMessagingException with a Custom Label and a stable code:
[1] The application is on, the plan includes Workflow Actions (and Apex, for an Apex action), and the
    user's own settings allow them (AIUserSettings__c.WorkflowActionsEnabled__c, off unless set).
[2] The action is read in system mode, because the User permission set cannot read it, and must be
    active and assigned to the agent through an active assignment.
[3] An action that requires confirmation runs only when the user has confirmed.
[4] The Apex class (checked to implement IAIWorkflowActionExecutor before it is instantiated) or the
    Flow runs as the signed-in user. A failure is logged in full and the user sees the Action Failed
    label, never class or flow names.
Whatever happens at [1] to [4] is recorded as a Workflow Action step on the reply the action was
suggested on: Success, Failed, or Blocked (refused before it ran), with the target, whether
confirmation was required and who confirmed it. cancel records that the user declined.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from AIWorkflowActionDispatcher. Adds the plan and user gates, system-mode read of the definition, the assignment check, confirmation, the interface check before instantiation, and evidence on every outcome.
2.0          Chandler Stuart          Apex class lookup uses Type.forName with an empty namespace so a subscriber's own class is found from managed code.
*/

public inherited sharing class AIWorkflowActionDispatcher {
  private static final String FLOW_OUTPUT_VARIABLE_NAME = 'output'; // A convention: Apex cannot discover a Flow's declared outputs.

  // messageId is the reply the action was suggested on, where the evidence is recorded. recordId may be null for an action that does not work on a record.
  public static Object runWorkflowAction(
    Id workflowActionId,
    Id agentId,
    Id messageId,
    Id recordId,
    Map<String, Object> inputParameters,
    Boolean isConfirmed
  ) {
    AIWorkflowAction__c action = null;
    Boolean hasRun = false;
    Long startedAt = System.currentTimeMillis();
    Object output = null;
    AIMessagingException problem = null;

    try {
      if (!AIAssistSettingsService.isEnabled())
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_APPLICATION_DISABLED,
          Label.AI_Error_Application_Inactive
        );
      if (!AIPlanLimitService.isWorkflowActionsAllowed())
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_PLAN_ACTIONS_NOT_INCLUDED,
          Label.AI_Error_Plan_Actions_Not_Included
        );

      AIUserSettings__c userSettings = AIMessagingSelector.getUserSettings(
        UserInfo.getUserId()
      );
      if (
        userSettings == null ||
        userSettings.IsActive__c != true ||
        userSettings.WorkflowActionsEnabled__c != true
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
          Label.AI_Error_Action_Not_Permitted
        );

      action = AIMessagingSelector.getAssignedAction(workflowActionId, agentId);
      if (action == null)
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED,
          Label.AI_Error_Action_Not_Permitted
        );

      if (action.RequiresConfirmation__c == true && isConfirmed != true)
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_ACTION_CONFIRMATION_REQUIRED,
          Label.AI_Error_Action_Confirmation_Required
        );

      Map<String, Object> parameters = inputParameters == null
        ? new Map<String, Object>()
        : inputParameters;
      hasRun = true;

      if (
        action.ActionType__c ==
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX
      ) {
        if (!AIPlanLimitService.isApexAllowed()) {
          hasRun = false;
          throw AIMessagingException.newRefusal(
            AIAssistApplicationConstants.ERROR_PLAN_APEX_NOT_INCLUDED,
            Label.AI_Error_Plan_Apex_Not_Included
          );
        }
        if (String.isBlank(action.ApexClassName__c))
          throw AIMessagingException.newFailure(
            'Action ' + action.DeveloperName__c + ' has no Apex class.',
            null
          );

        // Checked before anything in the class runs: the name was typed by a subscriber, and even constructing a class runs its code. The empty namespace makes the lookup find the subscriber's own unprefixed classes; the one-argument form looks only in the package's namespace once this is managed code.
        Type apexType = Type.forName('', action.ApexClassName__c.trim());
        if (
          apexType == null ||
          !IAIWorkflowActionExecutor.class.isAssignableFrom(apexType)
        )
          throw AIMessagingException.newFailure(
            'Apex class ' +
              action.ApexClassName__c +
              ' was not found or does not implement IAIWorkflowActionExecutor.',
            null
          );

        output = ((IAIWorkflowActionExecutor) apexType.newInstance())
          .execute(recordId, parameters);
      } else if (
        action.ActionType__c ==
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW
      ) {
        if (String.isBlank(action.FlowAPIName__c))
          throw AIMessagingException.newFailure(
            'Action ' + action.DeveloperName__c + ' has no Flow.',
            null
          );

        Map<String, Object> flowInputs = new Map<String, Object>(parameters);
        if (recordId != null)
          flowInputs.put('recordId', recordId);

        Flow.Interview interview = Flow.Interview.createInterview(
          action.FlowAPIName__c,
          flowInputs
        );
        interview.start();
        output = interview.getVariableValue(FLOW_OUTPUT_VARIABLE_NAME);
      } else {
        throw AIMessagingException.newFailure(
          'Action ' + action.DeveloperName__c + ' has an unsupported type.',
          null
        );
      }
    } catch (AIMessagingException caughtException) {
      if (caughtException.isRefusal) {
        problem = caughtException;
        if (
          caughtException.code ==
          AIAssistApplicationConstants.ERROR_ACTION_NOT_PERMITTED
        )
          AIViolationService.recordDeterministicViolation(
            AIAssistApplicationConstants.VIOLATION_TYPE_UNAUTHORIZED_WORKFLOW_ACTION,
            agentId,
            UserInfo.getUserId(),
            null,
            messageId
          );
      } else {
        AIPlatformLogManager.logCustomMessage(
          caughtException.getMessage(),
          caughtException.detail,
          'AIWorkflowActionDispatcher',
          'execute',
          workflowActionId
        );
        problem = AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_ACTION_FAILED,
          Label.AI_Error_Action_Failed
        );
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIWorkflowActionDispatcher',
        'runWorkflowAction'
      );
      problem = AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_ACTION_FAILED,
        Label.AI_Error_Action_Failed
      );
    }

    String status = problem == null
      ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS
      : (hasRun &&
          problem.code == AIAssistApplicationConstants.ERROR_ACTION_FAILED
          ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED
          : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED);

    // A refusal before the action was even read has nothing to attach the evidence to.
    AIExecutionStepRecorder.recordWorkflowActionStep(
      messageId,
      action,
      recordId,
      status,
      isConfirmed,
      System.currentTimeMillis() - startedAt
    );

    if (problem != null)
      throw problem;

    return output;
  }

  // The user declined at the confirmation. Nothing ran; this is the evidence that it was offered and refused.
  public static void recordDeclinedAction(
    Id workflowActionId,
    Id agentId,
    Id messageId,
    Id recordId
  ) {
    AIExecutionStepRecorder.recordWorkflowActionStep(
      messageId,
      AIMessagingSelector.getAssignedAction(workflowActionId, agentId),
      recordId,
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED,
      false,
      0
    );
  }
}
