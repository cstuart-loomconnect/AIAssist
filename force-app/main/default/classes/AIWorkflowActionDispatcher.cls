/*
Class Name: AIWorkflowActionDispatcher

=================================================================
=================================================================

Description: Runs one Workflow Action a user has chosen to run from a suggestion in the chat. The counterpart of
AIDataSourceDispatcher, with the extra care an action that can change data needs.

In order, and each refusal is an exception whose message is a Custom Label:
[1] The application is on and the user may run Workflow Actions: the AIAssistRunActions custom permission, or Workflow Actions Enabled on
    their policy or settings (AIFeatureService.isFeatureEnabled, one check for all three).
    The agent is active and still admits the user (AIMessageValidator.isUserAllowedOnAgent), so a user
    who has been removed from an agent cannot run an action it suggested earlier.
[2] The action is read in system mode, because the User permission set cannot read it, and must be
    active and assigned to the agent through an active assignment.
[3] An action that requires confirmation runs only when the user has confirmed.
[4] Only the inputs the action declares in InputSchema__c reach the Apex class or the Flow; any other key
    the browser sent is dropped and logged by name. recordId is never taken from the browser: it is the
    conversation's own record, set here.
[5] An Apex class (checked to implement IAIWorkflowActionExecutor before it is instantiated) runs in the
    user's transaction with the sharing it declares for itself. A Flow does not run as the user: a Flow
    started from Apex runs in system context, so the user's object and field permissions are not applied,
    and only record sharing is (this class is called from the with sharing chat controller). So before a
    Flow starts, the user must have access to every record Id passed to it (UserRecordAccess: read, or
    edit when the action's Execution Type is Write). A failure is logged in full and the user sees the Action
    Failed label, never class or flow names.
Whatever happens at [1] to [5] is recorded as a Workflow Action step on the reply the action was
suggested on: Success, Failed, or Blocked (refused before it ran), with the target, whether
confirmation was required and who confirmed it. cancel records that the user declined.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from AIWorkflowActionDispatcher. Adds the plan and user gates, system-mode read of the definition, the assignment check, confirmation, the interface check before instantiation, and evidence on every outcome.
2.0          Chandler Stuart          Apex class lookup uses Type.forName with an empty namespace so a subscriber's own class is found from managed code.
3.0          Chandler Stuart          The agent must still admit the user; inputs not declared in InputSchema__c are dropped; a Flow in system context without sharing is refused at run time.
4.0          Chandler Stuart          recordId is always the server's. The user's access to every record Id passed to a Flow is checked before it starts. Comments corrected: a Flow started from Apex runs in system context, not as the user.
*/

public inherited sharing class AIWorkflowActionDispatcher {
  public class AIWorkflowActionDispatcherException extends Exception {
  }

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
    Exception problem = null;

    try {
      // The application, then the user (AIFeatureService). The layer that refused chooses what the user is told.
      String blockedBy = AIFeatureService.getBlockingLayer(
        AIAssistApplicationConstants.APP_FEATURE_RUN_ACTIONS,
        AIUsagePolicyResolver.getUserSettings(UserInfo.getUserId())
      );
      // The application switch is reported first, as it always was: with AI Assist off nothing else matters.
      if (
        !AIAssistSettingsService.isEnabled() ||
        blockedBy == AIFeatureService.LAYER_ORG
      )
        throw new AIWorkflowActionDispatcherException(
          Label.AI_Error_Application_Inactive
        );
      if (blockedBy == AIFeatureService.LAYER_USER)
        throw new AIWorkflowActionDispatcherException(
          Label.AI_Error_Action_Not_Permitted
        );

      // The same access check the message validator makes: an inactive agent, or one the user has since been removed from, runs nothing.
      AIAgent__c agent = getAgent(agentId);
      if (
        agent == null ||
        agent.IsActive__c != true ||
        !AIMessageValidator.isUserAllowedOnAgent(agent, UserInfo.getUserId())
      )
        throw new AIWorkflowActionDispatcherException(
          Label.AI_Error_Action_Not_Permitted
        );

      action = getAssignedAction(workflowActionId, agentId);
      if (action == null)
        throw new AIWorkflowActionDispatcherException(
          Label.AI_Error_Action_Not_Permitted
        );

      if (action.RequiresConfirmation__c == true && isConfirmed != true)
        throw new AIWorkflowActionDispatcherException(
          Label.AI_Error_Action_Confirmation_Required
        );

      Map<String, Object> parameters = filterDeclaredInputs(
        action.InputSchema__c,
        inputParameters,
        workflowActionId
      );
      // recordId is the conversation's record and nothing else, even when the schema declares an input of that name.
      for (String declaredName : parameters.keySet().clone()) {
        if (declaredName.equalsIgnoreCase('recordId'))
          parameters.remove(declaredName);
      }
      hasRun = true;

      if (
        action.ActionType__c ==
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX
      ) {
        if (String.isBlank(action.ApexClassName__c)) {
          AIPlatformLogManager.logCustomMessage(
            'Action ' + action.DeveloperName__c + ' has no Apex class.',
            null,
            'AIWorkflowActionDispatcher',
            'runWorkflowAction',
            null
          );
          throw new AIWorkflowActionDispatcherException(
            Label.AI_Error_Action_Failed
          );
        }

        // Checked before anything in the class runs: the name was typed by a subscriber, and even constructing a class runs its code. The empty namespace makes the lookup find the subscriber's own unprefixed classes; the one-argument form looks only in the package's namespace once this is managed code.
        Type apexType = Type.forName('', action.ApexClassName__c.trim());
        if (
          apexType == null ||
          !IAIWorkflowActionExecutor.class.isAssignableFrom(apexType)
        ) {
          AIPlatformLogManager.logCustomMessage(
            'Apex class ' +
              action.ApexClassName__c +
              ' was not found or does not implement IAIWorkflowActionExecutor.',
            null,
            'AIWorkflowActionDispatcher',
            'runWorkflowAction',
            null
          );
          throw new AIWorkflowActionDispatcherException(
            Label.AI_Error_Action_Failed
          );
        }

        List<AIConversationMessage__c> suggestingMessages = messageId == null
          ? new List<AIConversationMessage__c>()
          : [
              SELECT AIConversation__c
              FROM AIConversationMessage__c
              WHERE Id = :messageId
              WITH SYSTEM_MODE
              LIMIT 1
            ];
        AIWorkflowActionRequest request = new AIWorkflowActionRequest();
        request.recordId = recordId;
        request.inputParameters = new Map<String, Object>(parameters);
        request.conversationId = suggestingMessages.isEmpty()
          ? null
          : suggestingMessages[0].AIConversation__c;
        request.agentId = agentId;
        request.userId = UserInfo.getUserId();
        request.actionName = action.DeveloperName__c;
        request.isConfirmed = isConfirmed == true;

        AIWorkflowActionResponse response = ((IAIWorkflowActionExecutor) apexType.newInstance())
          .execute(request);
        output = response == null ? null : response.message;
      } else if (
        action.ActionType__c ==
        AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW
      ) {
        if (String.isBlank(action.FlowAPIName__c)) {
          AIPlatformLogManager.logCustomMessage(
            'Action ' + action.DeveloperName__c + ' has no Flow.',
            null,
            'AIWorkflowActionDispatcher',
            'runWorkflowAction',
            null
          );
          throw new AIWorkflowActionDispatcherException(
            Label.AI_Error_Action_Failed
          );
        }

        Map<String, Object> flowInputs = new Map<String, Object>(parameters);
        if (recordId != null)
          flowInputs.put('recordId', recordId);

        // The Flow runs in system context, so the user's access to each record it is handed is checked here. A value that is not a record Id is not a record and is passed as it is.
        Map<Id, String> inputNameByRecordId = new Map<Id, String>();
        for (String inputName : flowInputs.keySet()) {
          Id passedId = flowInputs.get(inputName) instanceof Id ||
            flowInputs.get(inputName) instanceof String
            ? AIChatDataStructure.toIdOrNull(
                String.valueOf(flowInputs.get(inputName))
              )
            : null;
          if (passedId != null)
            inputNameByRecordId.put(passedId, inputName);
        }

        Boolean isWrite =
          action.ExecutionType__c ==
          AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
        Set<Id> refusedRecordIds = inputNameByRecordId.keySet().clone();
        if (
          refusedRecordIds.size() <=
          AIAssistApplicationConstants.MAX_FLOW_RECORD_INPUTS
        ) {
          for (UserRecordAccess access : [
            SELECT RecordId, HasReadAccess, HasEditAccess
            FROM UserRecordAccess
            WHERE
              UserId = :UserInfo.getUserId()
              AND RecordId IN :inputNameByRecordId.keySet()
            WITH SYSTEM_MODE
          ]) {
            if (isWrite ? access.HasEditAccess : access.HasReadAccess)
              refusedRecordIds.remove(access.RecordId);
          }
        }

        if (!refusedRecordIds.isEmpty()) {
          List<String> refusedInputs = new List<String>();
          for (Id refusedRecordId : refusedRecordIds)
            refusedInputs.add(
              inputNameByRecordId.get(refusedRecordId) + ' = ' + refusedRecordId
            );
          AIPlatformLogManager.logCustomMessage(
            'Flow action ' +
              action.DeveloperName__c +
              ' was not run: user ' +
              UserInfo.getUserId() +
              ' has no ' +
              (isWrite ? 'edit' : 'read') +
              ' access to a record passed to the Flow.',
            'Share the record with the user, or change the action so it does not pass it. Inputs refused: ' +
            String.join(refusedInputs, ', ').abbreviate(900),
            'AIWorkflowActionDispatcher',
            'runWorkflowAction',
            workflowActionId
          );
          hasRun = false;
          throw new AIWorkflowActionDispatcherException(
            Label.AI_Error_Action_Not_Permitted
          );
        }

        Flow.Interview interview = Flow.Interview.createInterview(
          action.FlowAPIName__c,
          flowInputs
        );
        interview.start();
        output = interview.getVariableValue(FLOW_OUTPUT_VARIABLE_NAME);
      } else {
        {
          AIPlatformLogManager.logCustomMessage(
            'Action ' + action.DeveloperName__c + ' has an unsupported type.',
            null,
            'AIWorkflowActionDispatcher',
            'runWorkflowAction',
            null
          );
          throw new AIWorkflowActionDispatcherException(
            Label.AI_Error_Action_Failed
          );
        }
      }
    } catch (Exception caughtException) {
      if (caughtException.getTypeName().startsWith('System.')) {
        AIPlatformLogManager.logException(
          caughtException,
          'AIWorkflowActionDispatcher',
          'runWorkflowAction'
        );
        problem = new AIWorkflowActionDispatcherException(
          Label.AI_Error_Action_Failed
        );
      } else {
        problem = caughtException;
      }
    }

    String status = problem == null
      ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS
      : (hasRun && problem.getMessage() == Label.AI_Error_Action_Failed
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

  // Keeps only the inputs InputSchema__c declares as properties. The values come from the browser, which can send anything, so a key the action never asked for is not passed on. A blank or malformed schema declares nothing, so nothing is passed. Dropped names are logged (never their values, which may be personal data).
  @TestVisible
  private static Map<String, Object> filterDeclaredInputs(
    String inputSchema,
    Map<String, Object> submittedInputs,
    Id workflowActionId
  ) {
    Map<String, Object> declaredInputs = new Map<String, Object>();

    if (submittedInputs == null || submittedInputs.isEmpty())
      return declaredInputs;

    Set<String> declaredNames = new Set<String>();
    if (String.isNotBlank(inputSchema)) {
      try {
        Object properties = ((Map<String, Object>) JSON.deserializeUntyped(
            inputSchema
          ))
          .get('properties');
        if (properties instanceof Map<String, Object>)
          declaredNames.addAll(((Map<String, Object>) properties).keySet());
      } catch (Exception malformedSchema) {
        declaredNames.clear(); // Nothing is declared, so nothing is passed.
      }
    }

    List<String> droppedNames = new List<String>();
    for (String submittedName : submittedInputs.keySet()) {
      if (declaredNames.contains(submittedName))
        declaredInputs.put(submittedName, submittedInputs.get(submittedName));
      else
        droppedNames.add(submittedName);
    }

    if (!droppedNames.isEmpty()) {
      droppedNames.sort();
      AIPlatformLogManager.logCustomMessage(
        'Inputs not declared by the action were dropped.',
        String.join(droppedNames, ', ').abbreviate(1000),
        'AIWorkflowActionDispatcher',
        'filterDeclaredInputs',
        workflowActionId
      );
    }

    return declaredInputs;
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
      getAssignedAction(workflowActionId, agentId),
      recordId,
      AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED,
      false,
      0
    );
  }

  // These queries must see every user's records, not just the running user's, so they run in a class declared without sharing.
  private static SystemReader systemReader = new SystemReader();

  @TestVisible
  private static AIAgent__c getAgent(Id agentId) {
    return systemReader.getAgent(agentId);
  }

  @TestVisible
  private static AIWorkflowAction__c getAssignedAction(
    Id actionId,
    Id agentId
  ) {
    return systemReader.getAssignedAction(actionId, agentId);
  }

  private without sharing class SystemReader {
    public AIAgent__c getAgent(Id agentId) {
      if (agentId == null)
        return null;

      List<AIAgent__c> agents = [
        SELECT
          Id,
          Name,
          DeveloperName__c,
          AIAgentPersona__c,
          IsActive__c,
          AccessMode__c,
          AIModelConfiguration__c,
          MaxMessagesPerConversation__c,
          MaxTokensPerConversation__c,
          MaxToolCallingIterations__c,
          SingleActiveConversationPerRecord__c,
          TokenTrackingMethod__c
        FROM AIAgent__c
        WHERE Id = :agentId
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      return agents.isEmpty() ? null : agents[0];
    }

    // One action the agent may offer: active, and linked to the agent through an active assignment. Null when it is neither.
    public AIWorkflowAction__c getAssignedAction(Id actionId, Id agentId) {
      if (actionId == null || agentId == null)
        return null;

      List<AIWorkflowAction__c> actions = [
        SELECT
          Id,
          DeveloperName__c,
          ActionName__c,
          ActionType__c,
          ExecutionType__c,
          ApexClassName__c,
          FlowAPIName__c,
          TargetObject__c,
          RequiresConfirmation__c,
          InputSchema__c
        FROM AIWorkflowAction__c
        WHERE
          Id = :actionId
          AND IsActive__c = TRUE
          AND Id IN (
            SELECT AIWorkflowAction__c
            FROM AIAgentWorkflowAction__c
            WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
          )
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      return actions.isEmpty() ? null : actions[0];
    }
  }
}
