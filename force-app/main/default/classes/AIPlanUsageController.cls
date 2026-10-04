/*
Class Name: AIPlanUsageController

=================================================================
=================================================================

Description: What the organisation has used of its plan and of the org's limits, for an administrator's
usage page. Read-only. Requires the AIAssistManageConfiguration custom permission.

- This month's messages and tokens against the plan's allowances, from the running totals AIOrgUsageService
  keeps (no usage row is read).
- Active agents, data sources and Workflow Actions against the plan's limits.
- Which features the plan includes.
- Storage: what AI Assist's records take now, and a projection of what they will take in 30 days at this
  month's rate (three records a message: the message, its reply and one step, at 2 KB each).
- AI Assist's own footprint against the org's limits, the mode each feature is in, and the thresholds
  that decide it (AIOrgLimitMonitor).

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public with sharing class AIPlanUsageController {
  public class Allowance {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal used = 0;
    @AuraEnabled
    public Decimal allowed; // Null: unlimited.
    @AuraEnabled
    public Integer percentUsed; // Null when unlimited.
  }

  public class FeatureLimit {
    @AuraEnabled
    public String feature;
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public Integer orgPercent; // How full the org's limit is.
    @AuraEnabled
    public Integer appPercent; // AI Assist's own share of it.
    @AuraEnabled
    public Integer degradedPercent;
    @AuraEnabled
    public Integer pausedPercent;
    @AuraEnabled
    public Integer appSharePercent; // Null: no share budget.
  }

  public class PlanUsage {
    @AuraEnabled
    public List<Allowance> monthly = new List<Allowance>();
    @AuraEnabled
    public List<Allowance> configuration = new List<Allowance>();
    @AuraEnabled
    public Map<String, Boolean> features = new Map<String, Boolean>();
    @AuraEnabled
    public Decimal storageMegabytes = 0;
    @AuraEnabled
    public Decimal projectedStorageMegabytes = 0;
    @AuraEnabled
    public Decimal asyncJobsLastDay = 0;
    @AuraEnabled
    public Decimal eventsLastDay = 0;
    @AuraEnabled
    public List<FeatureLimit> limits = new List<FeatureLimit>();
    @AuraEnabled
    public String renewsOn; // The first day of next month, when the monthly allowances start again.
  }

  private static final Integer RECORDS_PER_MESSAGE = 3;
  private static final Integer PROJECTION_DAYS = 30;

  @AuraEnabled
  public static PlanUsage getPlanUsage() {
    try {
      AIConfigurationAccess.assertCanManage(false);
      PlanUsage planUsage = new PlanUsage();
      Date today = AIAssistGlobalUtility.getOrgToday();
      AIMessagingSelector.OrgUsage orgUsage = AIOrgUsageService.getUsage();

      planUsage.monthly.add(
        toAllowance(
          'Messages',
          orgUsage.month.messages,
          AIPlanLimitService.getMessageLimit()
        )
      );
      planUsage.monthly.add(
        toAllowance(
          'Tokens',
          orgUsage.month.tokens,
          AIPlanLimitService.getUsageLimit()
        )
      );
      planUsage.renewsOn = today.toStartOfMonth().addMonths(1).format();

      planUsage.configuration.add(
        toAllowance(
          'Active agents',
          [
            SELECT COUNT()
            FROM AIAgent__c
            WHERE IsActive__c = TRUE
            WITH SYSTEM_MODE
          ],
          AIPlanLimitService.getActiveAgentLimit()
        )
      );
      planUsage.configuration.add(
        toAllowance(
          'Active data sources',
          [
            SELECT COUNT()
            FROM AIDataSource__c
            WHERE IsActive__c = TRUE
            WITH SYSTEM_MODE
          ],
          AIPlanLimitService.getActiveDataSourceLimit()
        )
      );
      planUsage.configuration.add(
        toAllowance(
          'Active workflow actions',
          [
            SELECT COUNT()
            FROM AIWorkflowAction__c
            WHERE IsActive__c = TRUE
            WITH SYSTEM_MODE
          ],
          AIPlanLimitService.getActiveActionLimit()
        )
      );

      for (
        String parameterName : new List<String>{
          AIAssistApplicationConstants.FEATURE_WORKFLOW_ACTIONS_ALLOWED,
          AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
          AIAssistApplicationConstants.FEATURE_AI_EVALUATED_RULES_ALLOWED,
          AIAssistApplicationConstants.FEATURE_MULTIPLE_PROVIDERS_ALLOWED,
          AIAssistApplicationConstants.FEATURE_BETA_FEATURES_ENABLED,
          AIAssistApplicationConstants.FEATURE_CONTINUATION_CHAT_ENABLED
        }
      )
        planUsage.features.put(
          parameterName,
          AIPlanLimitService.isAllowed(parameterName)
        );

      // Storage now, and in 30 days at this month's daily rate.
      AIOrgLimitMonitor.Footprint footprint = AIOrgLimitMonitor.getFootprint();
      planUsage.storageMegabytes = footprint.storageMegabytes;
      planUsage.asyncJobsLastDay = footprint.asyncJobs;
      planUsage.eventsLastDay = footprint.events;
      Decimal messagesPerDay = orgUsage.month.messages / today.day();
      planUsage.projectedStorageMegabytes = (footprint.storageMegabytes +
        messagesPerDay *
        PROJECTION_DAYS *
        RECORDS_PER_MESSAGE *
        AIAssistApplicationConstants.STORAGE_KILOBYTES_PER_RECORD / 1024)
        .setScale(2);

      AIOrgLimitMonitor.State state = AIOrgLimitMonitor.getState();
      for (
        String feature : new List<String>{
          AIAssistApplicationConstants.LIMIT_FEATURE_CHAT,
          AIAssistApplicationConstants.LIMIT_FEATURE_EVENTS,
          AIAssistApplicationConstants.LIMIT_FEATURE_LOGGING
        }
      ) {
        AIOrgLimitMonitor.FeatureState featureState = state.byFeature.get(
          feature
        );
        AIOrgLimitMonitor.Thresholds thresholds = AIOrgLimitMonitor.getThresholds(
          feature
        );
        FeatureLimit featureLimit = new FeatureLimit();
        featureLimit.feature = feature;
        featureLimit.mode = featureState == null
          ? AIAssistApplicationConstants.LIMIT_MODE_NORMAL
          : featureState.mode;
        featureLimit.orgPercent = featureState == null
          ? 0
          : featureState.percent;
        featureLimit.appPercent = featureState == null
          ? 0
          : featureState.appPercent;
        featureLimit.degradedPercent = thresholds.degraded;
        featureLimit.pausedPercent = thresholds.paused;
        featureLimit.appSharePercent = thresholds.appShare;
        planUsage.limits.add(featureLimit);
      }

      return planUsage;
    } catch (Exception caughtException) {
      throw AIConfigurationAccess.toAura(
        caughtException,
        'AIPlanUsageController',
        'getPlanUsage'
      );
    }
  }

  private static Allowance toAllowance(
    String name,
    Decimal used,
    Integer allowed
  ) {
    Allowance allowance = new Allowance();
    allowance.name = name;
    allowance.used = used == null ? 0 : used;
    allowance.allowed = allowed;
    allowance.percentUsed = allowed == null
      ? null
      : (allowed <= 0
          ? 100
          : (100 *
              allowance.used /
              allowed)
              .round(System.RoundingMode.DOWN)
              .intValue());

    return allowance;
  }
}
