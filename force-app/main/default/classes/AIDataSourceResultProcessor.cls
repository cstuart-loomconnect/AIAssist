/*
Class Name: AIDataSourceResultProcessor

=================================================================
=================================================================

Description: Turns the records a data source returned into plain maps and lists that are safe to hand to the model. It fails closed: a field or record it cannot process is left out or redacted, and a failure of the whole batch throws so it is never mistaken for "no records found".

Step 1: Describe every object type in the batch once
Step 2: Leave out fields the running user cannot read
Step 3: Replace values in personal data fields with a stand-in, the same one each time within the conversation
Step 4: Follow parent lookups (up to 4 deep) and child subqueries (up to 3 deep)
Step 5: Return one map per record

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIDataSourceResultProcessor {
  public class AIDataSourceResultProcessorException extends Exception {
  }

  // Turns the records into maps safe for the model. conversationId is the conversation the masked pairings are remembered against.
  public static List<Object> processResults(
    List<SObject> records,
    Id conversationId
  ) {
    try {
      // [1] Nothing to do - no records
      List<Object> processed = new List<Object>();
      if (records == null || records.isEmpty())
        return processed;

      // [2] Collect each distinct object type in the batch, so it is described once and not once per record
      Set<String> objectApiNames = new Set<String>();
      for (SObject record : records) {
        if (record != null)
          objectApiNames.add(record.getSObjectType().getDescribe().getName());
      }

      // [3] Describe those types with a single call
      Map<Schema.SObjectType, Schema.DescribeSObjectResult> describeByType = new Map<Schema.SObjectType, Schema.DescribeSObjectResult>();
      for (
        Schema.DescribeSObjectResult describeResult : Schema.describeSObjects(
          new List<String>(objectApiNames),
          SObjectDescribeOptions.DEFERRED
        )
      )
        describeByType.put(describeResult.getSObjectType(), describeResult);

      // [4] Flatten each record
      for (SObject record : records)
        processed.add(flatten(record, conversationId, 0, 0, describeByType));

      return processed;
    } catch (Exception ex) {
      // [5] Throw rather than return an empty list, because the model would read that as "no records found". No data is returned, so it still fails closed
      throw new AIDataSourceResultProcessorException(
        'Failed to process AI Data Source results: ' + ex.getMessage(),
        ex
      );
    }
  }

  // Builds one record's readable fields, masking personal data, plus its populated parents and children, up to the depth caps.
  private static Map<String, Object> flatten(
    SObject record,
    Id conversationId,
    Integer parentDepth,
    Integer childDepth,
    Map<Schema.SObjectType, Schema.DescribeSObjectResult> describeByType
  ) {
    try {
      // [1] Nothing to do - no record
      Map<String, Object> flattened = new Map<String, Object>();
      if (record == null)
        return flattened;

      // [2] Describe a type that was only found while following a parent or child
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

        // [3] Find the field. A parent shows up under its relationship name (Account), not its lookup field's name (AccountId), so the lookup's own access is the one checked
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

        // [4] Leave out a field the user cannot read, or one that cannot be found, rather than expose it
        if (fieldToken == null || !fieldToken.getDescribe().isAccessible())
          continue;

        if (rawValue instanceof SObject) {
          // [5] Stop climbing when the parent depth cap is reached
          if (
            parentDepth >=
            AIAssistApplicationConstants.DATA_SOURCE_RESULT_MAX_PARENT_DEPTH
          )
            continue;

          // [6] Flatten the parent one level deeper
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
          // [7] Replace personal data with a stand-in, whatever its type. A date of birth or an account number is personal data too, so it is masked by its text form
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
          // [8] Keep any other value as it is
          flattened.put(fieldApiName, rawValue);
        }
      }

      if (
        childDepth <
        AIAssistApplicationConstants.DATA_SOURCE_RESULT_MAX_CHILD_DEPTH
      ) {
        // [9] Work out which child relationships were queried. getSObjects() throws for any relationship that was not part of the query and an object has dozens, so checking the serialized keys avoids trial and error
        Set<String> queriedRelationships = ((Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(record)
          ))
          .keySet();

        for (
          Schema.ChildRelationship childRelationship : describeResult.getChildRelationships()
        ) {
          // [10] Skip a relationship that has no name or was not queried
          String relationshipName = childRelationship.getRelationshipName();
          if (
            String.isBlank(relationshipName) ||
            !queriedRelationships.contains(relationshipName)
          )
            continue;

          List<SObject> children = record.getSObjects(relationshipName);
          if (children == null)
            continue;

          // [11] Flatten each child one level deeper
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

      // [12] Return the flattened record
      return flattened;
    } catch (Exception ex) {
      // [13] Log the failure and return a redacted record, never the original
      AIPlatformLogManager.logException(
        ex,
        'AIDataSourceResultProcessor',
        'flatten'
      );
      return new Map<String, Object>{
        'error' => AIAssistApplicationConstants.DATA_SOURCE_RESULT_REDACTED_ERROR_VALUE
      };
    }
  }
}
