/*
Class Name: AIHealthCheckController

=================================================================
=================================================================

Description: Everything wrong with the configuration, in one list, each finding with the record to
open and fix. Read-only. Requires the AIAssistManageConfiguration custom permission.

What it looks for:
- The application is switched off, or its settings were activated in another org (a copied sandbox).
- The daily maintenance job is not scheduled.
- Broken references: an Apex class or Flow named by an active data source or Workflow Action that does
  not exist (or is not allowed), a permission set named by an active assignment that does not exist.
- Missing credentials: an active model configuration with no Named Credential, or one that does not exist.
- Retired models: a model configuration behind turns that failed as Model Retired in the last week.
- An active agent with no active model configuration.
- An active agent limited to assigned users with nobody assigned.

Configuration is read in system mode: the page is for an administrator and the findings name records,
not their content. Each query is capped, so a very large configuration is checked in part, never
failed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public with sharing class AIHealthCheckController {
  public class Finding {
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String severity; // Error stops something working; Warning does not yet.
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String recordName;
    @AuraEnabled
    public String recordUrl; // Relative, to open the record.
  }

  public static final String CODE_APP_INACTIVE = 'APP_INACTIVE';
  public static final String CODE_SANDBOX_NOT_ACTIVATED = 'SANDBOX_NOT_ACTIVATED';
  public static final String CODE_MAINTENANCE_NOT_SCHEDULED = 'MAINTENANCE_NOT_SCHEDULED';
  public static final String CODE_BROKEN_REFERENCE = 'BROKEN_REFERENCE';
  public static final String CODE_MISSING_CREDENTIAL = 'MISSING_CREDENTIAL';
  public static final String CODE_RETIRED_MODEL = 'RETIRED_MODEL';
  public static final String CODE_NO_ACTIVE_MODEL = 'NO_ACTIVE_MODEL';
  public static final String CODE_NO_ASSIGNED_USERS = 'NO_ASSIGNED_USERS';
  private static final Integer MAX_RECORDS_CHECKED = 500;

  // Named Credentials cannot be created in a test: when set, these are the ones that exist.
  @TestVisible
  private static Set<String> namedCredentialsForTest;

  @AuraEnabled
  public static List<Finding> getFindings() {
    try {
      AIConfigurationAccess.assertCanManage(false);
      List<Finding> findings = new List<Finding>();

      // The application and its housekeeping.
      if (AIAssistSettingsService.isActivatedElsewhere())
        findings.add(
          toFinding(
            CODE_SANDBOX_NOT_ACTIVATED,
            true,
            Label.AI_Console_Health_Sandbox,
            null,
            null
          )
        );
      else if (!AIAssistSettingsService.isEnabled())
        findings.add(
          toFinding(
            CODE_APP_INACTIVE,
            true,
            Label.AI_Console_Health_App_Inactive,
            null,
            null
          )
        );

      if (
        [
          SELECT COUNT()
          FROM CronTrigger
          WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
          WITH SYSTEM_MODE
        ] == 0
      )
        findings.add(
          toFinding(
            CODE_MAINTENANCE_NOT_SCHEDULED,
            false,
            Label.AI_Console_Health_No_Maintenance,
            null,
            null
          )
        );

      // Model configurations: the credential, and whether the provider has said the model is gone.
      List<AIModelConfiguration__c> models = [
        SELECT Id, Name, NamedCredential__c, ModelIdentifier__c
        FROM AIModelConfiguration__c
        WHERE IsActive__c = TRUE
        WITH SYSTEM_MODE
        ORDER BY Name
        LIMIT :MAX_RECORDS_CHECKED
      ];
      Set<String> credentialNames = new Set<String>();
      for (AIModelConfiguration__c model : models) {
        if (String.isNotBlank(model.NamedCredential__c))
          credentialNames.add(
            model.NamedCredential__c.contains('__')
              ? model.NamedCredential__c.substringAfter('__')
              : model.NamedCredential__c
          );
      }
      Set<String> existingCredentials = new Set<String>();
      if (namedCredentialsForTest != null) {
        for (String testName : namedCredentialsForTest)
          existingCredentials.add(testName.toLowerCase());
      } else {
        for (NamedCredential credential : [
          SELECT DeveloperName, NamespacePrefix
          FROM NamedCredential
          WHERE DeveloperName IN :credentialNames
          WITH SYSTEM_MODE
          LIMIT 2000
        ])
          existingCredentials.add(
            (String.isBlank(credential.NamespacePrefix)
                ? credential.DeveloperName
                : credential.NamespacePrefix + '__' + credential.DeveloperName)
              .toLowerCase()
          );
      }

      Set<Id> retiredModelIds = new Set<Id>();
      Datetime oneWeekAgo = System.now().addDays(-7);
      for (AIConversationMessage__c failedTurn : [
        SELECT AIConversation__r.AIAgent__r.AIModelConfiguration__c
        FROM AIConversationMessage__c
        WHERE
          FailureReason__c = :AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
          AND CreatedDate >= :oneWeekAgo
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
        LIMIT :MAX_RECORDS_CHECKED
      ])
        retiredModelIds.add(
          failedTurn.AIConversation__r?.AIAgent__r?.AIModelConfiguration__c
        );

      for (AIModelConfiguration__c model : models) {
        if (
          String.isBlank(model.NamedCredential__c) ||
          !existingCredentials.contains(model.NamedCredential__c.toLowerCase())
        )
          findings.add(
            toFinding(
              CODE_MISSING_CREDENTIAL,
              true,
              String.format(
                Label.AI_Console_Health_Credential_Missing,
                new List<String>{
                  model.Name,
                  String.isBlank(model.NamedCredential__c)
                    ? '-'
                    : model.NamedCredential__c
                }
              ),
              model.Id,
              model.Name
            )
          );
        if (retiredModelIds.contains(model.Id))
          findings.add(
            toFinding(
              CODE_RETIRED_MODEL,
              true,
              String.format(
                Label.AI_Console_Health_Model_Retired,
                new List<String>{ model.Name, model.ModelIdentifier__c }
              ),
              model.Id,
              model.Name
            )
          );
      }

      // Data sources and Workflow Actions: what they name must exist.
      for (AIDataSource__c dataSource : [
        SELECT Id, Name, ApexClassName__c
        FROM AIDataSource__c
        WHERE
          IsActive__c = TRUE
          AND SourceType__c = :AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX
        WITH SYSTEM_MODE
        ORDER BY Name
        LIMIT :MAX_RECORDS_CHECKED
      ]) {
        System.Type apexType = String.isBlank(dataSource.ApexClassName__c)
          ? null
          : Type.forName('', dataSource.ApexClassName__c.trim());
        if (
          apexType == null ||
          !IAIDataSourceExecutor.class.isAssignableFrom(apexType)
        )
          findings.add(
            toFinding(
              CODE_BROKEN_REFERENCE,
              true,
              String.format(
                Label.AI_Console_Health_Apex_Missing,
                new List<String>{ dataSource.Name, dataSource.ApexClassName__c }
              ),
              dataSource.Id,
              dataSource.Name
            )
          );
      }

      List<AIWorkflowAction__c> actions = [
        SELECT Id, Name, ActionType__c, ApexClassName__c, FlowAPIName__c
        FROM AIWorkflowAction__c
        WHERE IsActive__c = TRUE
        WITH SYSTEM_MODE
        ORDER BY Name
        LIMIT :MAX_RECORDS_CHECKED
      ];
      Set<String> flowNames = new Set<String>();
      for (AIWorkflowAction__c action : actions) {
        if (
          action.ActionType__c ==
          AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW &&
          String.isNotBlank(action.FlowAPIName__c)
        )
          flowNames.add(action.FlowAPIName__c);
      }
      Map<String, Boolean> isFlowAllowed = AIFlowRunModeService.getAllowedByFlowName(
        flowNames
      );
      for (AIWorkflowAction__c action : actions) {
        if (
          action.ActionType__c ==
          AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX
        ) {
          System.Type apexType = String.isBlank(action.ApexClassName__c)
            ? null
            : Type.forName('', action.ApexClassName__c.trim());
          if (
            apexType == null ||
            !IAIWorkflowActionExecutor.class.isAssignableFrom(apexType)
          )
            findings.add(
              toFinding(
                CODE_BROKEN_REFERENCE,
                true,
                String.format(
                  Label.AI_Console_Health_Apex_Missing,
                  new List<String>{ action.Name, action.ApexClassName__c }
                ),
                action.Id,
                action.Name
              )
            );
        } else if (isFlowAllowed.get(action.FlowAPIName__c) != true) {
          findings.add(
            toFinding(
              CODE_BROKEN_REFERENCE,
              true,
              String.format(
                Label.AI_Console_Health_Flow_Missing,
                new List<String>{ action.Name, action.FlowAPIName__c }
              ),
              action.Id,
              action.Name
            )
          );
        }
      }

      // Agents: a model to answer with, and somebody to answer.
      List<AIAgent__c> agents = [
        SELECT
          Id,
          Name,
          AccessMode__c,
          AIModelConfiguration__r.IsActive__c,
          (
            SELECT PermissionSetName__c, AssigneeType__c
            FROM AIAgentAssignments__r
            WHERE IsActive__c = TRUE
            LIMIT 200
          )
        FROM AIAgent__c
        WHERE IsActive__c = TRUE
        WITH SYSTEM_MODE
        ORDER BY Name
        LIMIT :MAX_RECORDS_CHECKED
      ];
      Set<String> permissionSetNames = new Set<String>();
      for (AIAgent__c agent : agents) {
        for (AIAgentAssignment__c assignment : agent.AIAgentAssignments__r) {
          if (String.isNotBlank(assignment.PermissionSetName__c))
            permissionSetNames.add(assignment.PermissionSetName__c);
        }
      }
      Set<String> existingPermissionSets = new Set<String>();
      for (PermissionSet permissionSet : [
        SELECT Name
        FROM PermissionSet
        WHERE Name IN :permissionSetNames
        WITH SYSTEM_MODE
        LIMIT 2000
      ])
        existingPermissionSets.add(permissionSet.Name.toLowerCase());
      for (PermissionSetGroup permissionSetGroup : [
        SELECT DeveloperName
        FROM PermissionSetGroup
        WHERE DeveloperName IN :permissionSetNames
        WITH SYSTEM_MODE
        LIMIT 2000
      ])
        existingPermissionSets.add(
          permissionSetGroup.DeveloperName.toLowerCase()
        );

      for (AIAgent__c agent : agents) {
        if (agent.AIModelConfiguration__r?.IsActive__c != true)
          findings.add(
            toFinding(
              CODE_NO_ACTIVE_MODEL,
              true,
              String.format(
                Label.AI_Console_Health_Model_Inactive,
                new List<String>{ agent.Name }
              ),
              agent.Id,
              agent.Name
            )
          );
        if (
          agent.AccessMode__c ==
          AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY &&
          agent.AIAgentAssignments__r.isEmpty()
        )
          findings.add(
            toFinding(
              CODE_NO_ASSIGNED_USERS,
              false,
              String.format(
                Label.AI_Console_Health_No_Users,
                new List<String>{ agent.Name }
              ),
              agent.Id,
              agent.Name
            )
          );
        for (AIAgentAssignment__c assignment : agent.AIAgentAssignments__r) {
          if (
            String.isNotBlank(assignment.PermissionSetName__c) &&
            !existingPermissionSets.contains(
              assignment.PermissionSetName__c.toLowerCase()
            )
          )
            findings.add(
              toFinding(
                CODE_BROKEN_REFERENCE,
                true,
                String.format(
                  Label.AI_Console_Health_Permission_Set_Missing,
                  new List<String>{
                    agent.Name,
                    assignment.PermissionSetName__c
                  }
                ),
                agent.Id,
                agent.Name
              )
            );
        }
      }

      return findings;
    } catch (Exception caughtException) {
      throw AIConfigurationAccess.toAura(
        caughtException,
        'AIHealthCheckController',
        'getFindings'
      );
    }
  }

  private static Finding toFinding(
    String code,
    Boolean isError,
    String message,
    Id recordId,
    String recordName
  ) {
    Finding finding = new Finding();
    finding.code = code;
    finding.severity = isError
      ? AIAssistApplicationConstants.LOG_SEVERITY_ERROR
      : AIAssistApplicationConstants.LOG_SEVERITY_WARNING;
    finding.message = message;
    finding.recordId = recordId;
    finding.recordName = recordName;
    finding.recordUrl = recordId == null ? null : '/' + recordId;

    return finding;
  }
}
