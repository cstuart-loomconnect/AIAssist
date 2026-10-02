/*
Class Name: AIDataSourceResultProcessor

=================================================================
=================================================================

Description: Turns the records a data source returned into plain maps and lists that are safe to
hand to the model:
[1] Fields the running user cannot read are left out.
[2] A value in a field registered as personal data is replaced with a stand-in
    (AIPiiPseudonymizationService), consistently within the conversation. Text, dates and numbers
    alike: the stand-in replaces the value's text form.
[3] Parent lookups (up to 4 deep) and child subqueries (up to 3 deep) are followed.

It fails closed: a field or record it cannot process is omitted or redacted, never passed on
as it was. A failure of the whole batch throws, so it is never mistaken for "no records found".

The batch is described once, by object type, with a single describe call; the result is reused
for every record and every level of recursion.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          The conversation is a parameter, not a static the caller must remember to set. User-mode field check always applies. Single-use helpers inlined.
3.0          Chandler Stuart          Personal data that is not text (dates, numbers) is masked too, instead of being passed on as it was.
*/

public inherited sharing class AIDataSourceResultProcessor {
  public class AIDataSourceResultProcessorException extends Exception {
  }

  // conversationId is the conversation the masked pairings are remembered against.
  public static List<Object> processResults(
    List<SObject> records,
    Id conversationId
  ) {
    try {
      List<Object> processed = new List<Object>();

      if (records == null || records.isEmpty())
        return processed;

      // One describe call for every distinct type in the batch, not one per record.
      Set<String> objectApiNames = new Set<String>();
      for (SObject record : records) {
        if (record != null)
          objectApiNames.add(record.getSObjectType().getDescribe().getName());
      }

      Map<Schema.SObjectType, Schema.DescribeSObjectResult> describeByType = new Map<Schema.SObjectType, Schema.DescribeSObjectResult>();
      for (
        Schema.DescribeSObjectResult describeResult : Schema.describeSObjects(
          new List<String>(objectApiNames),
          SObjectDescribeOptions.DEFERRED
        )
      )
        describeByType.put(describeResult.getSObjectType(), describeResult);

      for (SObject record : records)
        processed.add(flatten(record, conversationId, 0, 0, describeByType));

      return processed;
    } catch (Exception caughtException) {
      throw new AIDataSourceResultProcessorException(
        'Failed to process AI Data Source results: ' +
        caughtException.getMessage(),
        caughtException
      ); // Not swallowed to an empty list: the model would read that as "no records found". Still fails closed, as no data is returned.
    }
  }

  // One record's readable fields, masking PII, plus its populated parents and children, recursively up to the depth caps.
  private static Map<String, Object> flatten(
    SObject record,
    Id conversationId,
    Integer parentDepth,
    Integer childDepth,
    Map<Schema.SObjectType, Schema.DescribeSObjectResult> describeByType
  ) {
    try {
      Map<String, Object> flattened = new Map<String, Object>();

      if (record == null)
        return flattened;

      // A type found only while recursing (a parent or child) is described on demand.
      if (!describeByType.containsKey(record.getSObjectType()))
        describeByType.put(
          record.getSObjectType(),
          record.getSObjectType().getDescribe()
        );

      Schema.DescribeSObjectResult describeResult = describeByType.get(
        record.getSObjectType()
      );
      String objectApiName = describeResult.getName();
      Map<String, Schema.SObjectField> fieldsByName = describeResult.fields.getMap();
      Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();

      for (String fieldApiName : populatedFields.keySet()) {
        Object rawValue = populatedFields.get(fieldApiName);

        // A traversed parent shows up under its relationship name ("Account"), not its lookup field's ("AccountId"), so the lookup's own access is the one checked. Unresolvable means hidden.
        Schema.SObjectField fieldToken = fieldsByName.get(fieldApiName);
        if (fieldToken == null) {
          for (Schema.SObjectField candidateField : fieldsByName.values()) {
            if (
              fieldApiName.equalsIgnoreCase(
                candidateField.getDescribe().getRelationshipName()
              )
            ) {
              fieldToken = candidateField;
              break;
            }
          }
        }

        if (fieldToken == null || !fieldToken.getDescribe().isAccessible())
          continue; // Not visible to the running user: omit rather than expose.

        if (rawValue instanceof SObject) {
          if (
            parentDepth >=
            AIAssistApplicationConstants.DATA_SOURCE_RESULT_MAX_PARENT_DEPTH
          )
            continue; // Depth cap reached: omit rather than keep climbing.
          flattened.put(
            fieldApiName,
            flatten(
              (SObject) rawValue,
              conversationId,
              parentDepth + 1,
              childDepth,
              describeByType
            )
          );
        } else if (
          rawValue != null &&
          String.isNotBlank(String.valueOf(rawValue)) &&
          AIPiiFieldRegistry.isPii(objectApiName, fieldApiName)
        ) {
          // Whatever its type: a date of birth or an account number is personal data too, and is masked by its text form.
          flattened.put(
            fieldApiName,
            AIPiiPseudonymizationService.pseudonymize(
              conversationId,
              objectApiName,
              fieldApiName,
              String.valueOf(rawValue)
            )
          );
        } else {
          flattened.put(fieldApiName, rawValue);
        }
      }

      if (
        childDepth <
        AIAssistApplicationConstants.DATA_SOURCE_RESULT_MAX_CHILD_DEPTH
      ) {
        // getSObjects() throws for any child relationship that was not part of the query's subqueries, and an object has dozens. Serializing once and checking which keys are present says which were queried, without the trial and error.
        Set<String> queriedRelationships = ((Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(record)
          ))
          .keySet();

        for (
          Schema.ChildRelationship childRelationship : describeResult.getChildRelationships()
        ) {
          String relationshipName = childRelationship.getRelationshipName();
          if (
            String.isBlank(relationshipName) ||
            !queriedRelationships.contains(relationshipName)
          )
            continue;

          List<SObject> children = record.getSObjects(relationshipName);
          if (children == null)
            continue;

          List<Object> flattenedChildren = new List<Object>();
          for (SObject child : children)
            flattenedChildren.add(
              flatten(
                child,
                conversationId,
                parentDepth,
                childDepth + 1,
                describeByType
              )
            );

          flattened.put(relationshipName, flattenedChildren);
        }
      }

      return flattened;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataSourceResultProcessor',
        'flatten'
      );
      return new Map<String, Object>{
        'error' => AIAssistApplicationConstants.DATA_SOURCE_RESULT_REDACTED_ERROR_VALUE
      };
    }
  }
}
