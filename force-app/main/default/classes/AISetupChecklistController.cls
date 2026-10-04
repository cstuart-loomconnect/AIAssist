/*
Class Name: AISetupChecklistController

=================================================================
=================================================================

Description: The Getting Started checklist: what an administrator still has to do before anyone can
chat, and the one step this page can do for them. Requires the AIAssistManageConfiguration custom
permission.

Steps, in order:
[1] Permission sets assigned: somebody holds AI Assist User, Super User or Admin.
[2] Credential tested: a model configuration has passed Test Connection (Connection Tested Date).
[3] First agent: an active agent exists.
[4] Assignment: that agent can be used by somebody (it is open to all AI Assist users, or has an active
    assignment).
[5] Maintenance scheduled: the daily job exists. scheduleMaintenance schedules it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public with sharing class AISetupChecklistController {
  public class Step {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Boolean isComplete = false;
  }

  public class Checklist {
    @AuraEnabled
    public List<Step> steps = new List<Step>();
    @AuraEnabled
    public Boolean isComplete = false;
  }

  public static final String STEP_PERMISSION_SETS = 'PermissionSetsAssigned';
  public static final String STEP_CREDENTIAL_TESTED = 'CredentialTested';
  public static final String STEP_FIRST_AGENT = 'FirstAgent';
  public static final String STEP_ASSIGNMENT = 'AgentAssigned';
  public static final String STEP_MAINTENANCE = 'MaintenanceScheduled';

  @AuraEnabled
  public static Checklist getChecklist() {
    try {
      AIConfigurationAccess.assertCanManage(false);
      Map<String, Boolean> completeByStep = new Map<String, Boolean>();

      completeByStep.put(
        STEP_PERMISSION_SETS,
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE
            PermissionSet.Name IN (
              :AIAssistApplicationConstants.PERMISSION_SET_USER,
              :AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER,
              :AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER
            )
            AND Assignee.IsActive = TRUE
          WITH SYSTEM_MODE
          LIMIT 1
        ] > 0
      );
      completeByStep.put(
        STEP_CREDENTIAL_TESTED,
        [
          SELECT COUNT()
          FROM AIModelConfiguration__c
          WHERE IsActive__c = TRUE AND ConnectionTestedDate__c != NULL
          WITH SYSTEM_MODE
          LIMIT 1
        ] > 0
      );
      completeByStep.put(
        STEP_FIRST_AGENT,
        [
          SELECT COUNT()
          FROM AIAgent__c
          WHERE IsActive__c = TRUE
          WITH SYSTEM_MODE
          LIMIT 1
        ] > 0
      );
      // Open to every AI Assist user, or assigned to somebody.
      completeByStep.put(
        STEP_ASSIGNMENT,
        [
            SELECT COUNT()
            FROM AIAgent__c
            WHERE
              IsActive__c = TRUE
              AND AccessMode__c = :AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS
            WITH SYSTEM_MODE
            LIMIT 1
          ] > 0 ||
          [
            SELECT COUNT()
            FROM AIAgentAssignment__c
            WHERE IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
          ] > 0
      );
      completeByStep.put(
        STEP_MAINTENANCE,
        [
          SELECT COUNT()
          FROM CronTrigger
          WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
          WITH SYSTEM_MODE
        ] > 0
      );

      Checklist checklist = new Checklist();
      checklist.isComplete = true;
      for (
        String stepName : new List<String>{
          STEP_PERMISSION_SETS,
          STEP_CREDENTIAL_TESTED,
          STEP_FIRST_AGENT,
          STEP_ASSIGNMENT,
          STEP_MAINTENANCE
        }
      ) {
        Step step = new Step();
        step.name = stepName;
        step.isComplete = completeByStep.get(stepName);
        checklist.steps.add(step);
        checklist.isComplete = checklist.isComplete && step.isComplete;
      }

      return checklist;
    } catch (Exception caughtException) {
      throw AIConfigurationAccess.toAura(
        caughtException,
        'AISetupChecklistController',
        'getChecklist'
      );
    }
  }

  // Schedules the daily maintenance job. True when it was scheduled now, false when it already was.
  @AuraEnabled
  public static Boolean scheduleMaintenance() {
    try {
      AIConfigurationAccess.assertCanManage(false);
      return AIMaintenanceScheduler.scheduleDaily() != null;
    } catch (Exception caughtException) {
      throw AIConfigurationAccess.toAura(
        caughtException,
        'AISetupChecklistController',
        'scheduleMaintenance'
      );
    }
  }
}
