/*
Class Name: AIPiiRegistrySyncWorker

=================================================================
=================================================================

Description: Refreshes the field metadata of the PII registry objects it is given.

Step 1: Read the registries it was given
Step 2: For each registry, read the object's fields and their Data Classification Compliance Group from FieldDefinition
Step 3: Classify each field's PII type with AIPiiFieldTypeClassifier
Step 4: Upsert one AIPIIFieldMetadata__c per field on FieldKey__c
Step 5: Mark each registry Synced, or Failed when anything went wrong with it

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistrySyncWorker implements Queueable {

    public class AIPiiRegistrySyncWorkerException extends Exception {}

    private List<Id> registryIds;

    // Keeps the Ids of the registries to sync.
    public AIPiiRegistrySyncWorker(List<Id> registryIds) {

        this.registryIds = registryIds;
    }

    // Syncs the field metadata of each registry. FieldDefinition is read with ordinary SOQL, so the worker makes no callout and never handles a session Id. A failure on one registry marks that registry Failed and the rest continue. Bounded: at most MAX_PII_REGISTRIES_PER_RUN registries and MaxFieldsToQuery__c fields each, so one job stays inside the query and DML limits. System mode: the User permission set cannot read the registry and the registry's fields are system-managed.
    public void execute(QueueableContext context) {

        // [1] Nothing to sync
        if (registryIds == null || registryIds.isEmpty()) return;

        // [2] Read the registries it was given
        List<AIPIIRegistry__c> registries = [SELECT Id, ObjectAPIName__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE Id IN :registryIds WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN];

        for (AIPIIRegistry__c registry : registries) {

            try {

                // [3] Work out how many fields to read for this object
                Integer maxFields = registry.MaxFieldsToQuery__c == null ? AIAssistApplicationConstants.DEFAULT_MAX_PII_FIELDS_TO_QUERY : Integer.valueOf(registry.MaxFieldsToQuery__c);
                String objectName = registry.ObjectAPIName__c;

                // [4] Read the object's fields
                List<FieldDefinition> fieldDefinitions = [SELECT QualifiedApiName, Label, DataType, ComplianceGroup FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = :objectName LIMIT :maxFields];
                List<AIPIIFieldMetadata__c> fieldMetadataRecords = new List<AIPIIFieldMetadata__c>();

                // [5] Build one metadata record per field. A field is PII when Data Classification flagged it
                for (FieldDefinition fieldDefinition : fieldDefinitions) {

                    fieldMetadataRecords.add(new AIPIIFieldMetadata__c(PIIRegistry__c = registry.Id, FieldKey__c = objectName + '.' + fieldDefinition.QualifiedApiName, FieldAPIName__c = fieldDefinition.QualifiedApiName, FieldLabel__c = fieldDefinition.Label, DataType__c = fieldDefinition.DataType, ComplianceGroup__c = fieldDefinition.ComplianceGroup, IsPII__c = String.isNotBlank(fieldDefinition.ComplianceGroup), PIIFieldType__c = AIPiiFieldTypeClassifier.classify(fieldDefinition.QualifiedApiName, fieldDefinition.Label, fieldDefinition.DataType, fieldDefinition.ComplianceGroup)));
                }

                // [6] Save them, matching on the field key so a repeat run updates the same rows
                List<Database.UpsertResult> upsertResults = Database.upsert(fieldMetadataRecords, AIPIIFieldMetadata__c.FieldKey__c, false, AccessLevel.SYSTEM_MODE);

                // [7] Fail the registry when any field could not be saved
                for (Database.UpsertResult upsertResult : upsertResults) {

                    if (!upsertResult.isSuccess()) {

                        AIPlatformLogManager.logCustomMessage('A field of ' + objectName + ' could not be saved: ' + upsertResult.getErrors()[0].getMessage(), null, 'AIPiiRegistrySyncWorker', 'execute', null);
                        throw new AIPiiRegistrySyncWorkerException(Label.AI_Error_Generic);
                    }
                }

                // [8] Mark the registry Synced, and clear the reset date so a past-due reset does not trigger every run
                registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_SYNCED;
                registry.LastSynced__c = System.now();
                registry.CacheResetDate__c = null;

            } catch (Exception ex) {

                AIPlatformLogManager.logException(ex, 'AIPiiRegistrySyncWorker', 'execute');
                registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED;
            }
        }

        // [9] Save the status of every registry
        AIMessagingDataService.updateAndLogFailures(registries, 'AIPiiRegistrySyncWorker', 'execute');
    }
}
