/*
Class Name: AIPiiRegistrySyncWorker

=================================================================
=================================================================

Description: Refreshes the field metadata of the PII registry objects it is given. For each registry it reads
FieldDefinition (the object's fields with their Data Classification Compliance Group), upserts one
AIPIIFieldMetadata__c per field on FieldKey__c, classifies each field's PII type, and marks the
registry Synced or Failed.

FieldDefinition is read with ordinary SOQL, so the worker makes no callout and never handles a
session Id. A failure on one registry marks that registry Failed and the rest continue.

Bounded: at most MAX_PII_REGISTRIES_PER_RUN registries and MaxFieldsToQuery__c fields each, so one
job stays inside the query and DML limits. System mode: the User permission set cannot read the
registry and the registry's fields are system-managed.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, from AIPiiRegistryWorker. Queueable instead of future, SOQL on FieldDefinition instead of a Tooling API callout with the session Id, one job for several registries.
*/

public inherited sharing class AIPiiRegistrySyncWorker implements Queueable {
  public class AIPiiRegistrySyncWorkerException extends Exception {
  }

  private List<Id> registryIds;

  public AIPiiRegistrySyncWorker(List<Id> registryIds) {
    this.registryIds = registryIds;
  }

  public void execute(QueueableContext context) {
    if (registryIds == null || registryIds.isEmpty())
      return;

    List<AIPIIRegistry__c> registries = [
      SELECT Id, ObjectAPIName__c, MaxFieldsToQuery__c
      FROM AIPIIRegistry__c
      WHERE Id IN :registryIds
      WITH SYSTEM_MODE
      LIMIT :AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN
    ];

    for (AIPIIRegistry__c registry : registries) {
      try {
        Integer maxFields = registry.MaxFieldsToQuery__c == null
          ? AIAssistApplicationConstants.DEFAULT_MAX_PII_FIELDS_TO_QUERY
          : Integer.valueOf(registry.MaxFieldsToQuery__c);
        String objectName = registry.ObjectAPIName__c;

        List<FieldDefinition> fieldDefinitions = [
          SELECT QualifiedApiName, Label, DataType, ComplianceGroup
          FROM FieldDefinition
          WHERE EntityDefinition.QualifiedApiName = :objectName
          LIMIT :maxFields
        ];
        List<AIPIIFieldMetadata__c> fieldMetadataRecords = new List<AIPIIFieldMetadata__c>();

        for (FieldDefinition fieldDefinition : fieldDefinitions) {
          fieldMetadataRecords.add(
            new AIPIIFieldMetadata__c(
              PIIRegistry__c = registry.Id,
              FieldKey__c = objectName + '.' + fieldDefinition.QualifiedApiName,
              FieldAPIName__c = fieldDefinition.QualifiedApiName,
              FieldLabel__c = fieldDefinition.Label,
              DataType__c = fieldDefinition.DataType,
              ComplianceGroup__c = fieldDefinition.ComplianceGroup,
              IsPII__c = String.isNotBlank(fieldDefinition.ComplianceGroup), // Flagged by Data Classification.
              PIIFieldType__c = AIPiiFieldTypeClassifier.classify(
                fieldDefinition.QualifiedApiName,
                fieldDefinition.Label,
                fieldDefinition.DataType,
                fieldDefinition.ComplianceGroup
              )
            )
          );
        }

        List<Database.UpsertResult> upsertResults = Database.upsert(
          fieldMetadataRecords,
          AIPIIFieldMetadata__c.FieldKey__c,
          false,
          AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult upsertResult : upsertResults) {
          if (!upsertResult.isSuccess()) {
            AIPlatformLogManager.logCustomMessage(
              'A field of ' +
                objectName +
                ' could not be saved: ' +
                upsertResult.getErrors()[0].getMessage(),
              null,
              'AIPiiRegistrySyncWorker',
              'execute',
              null
            );
            throw new AIPiiRegistrySyncWorkerException(Label.AI_Error_Generic);
          }
        }

        registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
        registry.LastSynced__c = System.now();
        registry.CacheResetDate__c = null; // Cleared so a past-due reset does not trigger every run.
      } catch (Exception caughtException) {
        AIPlatformLogManager.logException(
          caughtException,
          'AIPiiRegistrySyncWorker',
          'execute'
        );
        registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
      }
    }

    AIMessagingDataService.updateAndLogFailures(
      registries,
      'AIPiiRegistrySyncWorker',
      'execute'
    );
  }
}
