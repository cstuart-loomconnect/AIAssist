/*
Class Name: AIPiiMappingService

=================================================================
=================================================================

Description: Remembers, per conversation, which fake value stands in for which real value.

Step 1: Read the conversation's pairs from its one AIPIIMapping__c, once, and cache them both ways
Step 2: Add a new real/fake pair to the cache and to the record's JSON
Step 3: Save the record now, or hold it while writes are deferred
Step 4: Write every held record in one pass with saveCached(), after the last callout

Nobody is granted AIPIIMapping__c (it holds real values next to their fake ones), so this class
is the only reader and writer, and every query and write is explicit system mode. It is only
ever asked about a conversation the caller has already authorised.

While a turn's tool-calling loop is running, a write would block the next callout (uncommitted
work), so the agent manager sets isDeferringWrites.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiMappingService {
  private static Map<Id, Map<String, String>> realToFakeByConversation = new Map<Id, Map<String, String>>();
  private static Map<Id, Map<String, String>> fakeToRealByConversation = new Map<Id, Map<String, String>>();
  private static Map<Id, AIPIIMapping__c> recordByConversation = new Map<Id, AIPIIMapping__c>();
  private static Set<Id> unsavedConversationIds = new Set<Id>();

  // Set before a callout loop that may mask PII between callouts, and cleared once the callouts are done.
  public static Boolean isDeferringWrites = false;

  // Real value -> fake value for the conversation. Empty for anything that is not a conversation.
  public static Map<String, String> getMapping(Id conversationId) {
    // [1] Nothing to read - not a conversation
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType
    )
      return new Map<String, String>();

    if (!realToFakeByConversation.containsKey(conversationId)) {
      // [2] Load the conversation's AIPIIMapping__c once. System mode, because no permission set grants this object
      if (!recordByConversation.containsKey(conversationId)) {
        List<AIPIIMapping__c> existingMappings = [
          SELECT Id, MappingJson__c
          FROM AIPIIMapping__c
          WHERE AIConversation__c = :conversationId
          WITH SYSTEM_MODE
          LIMIT 1
        ];

        recordByConversation.put(
          conversationId,
          existingMappings.isEmpty() ? null : existingMappings[0]
        );
      }

      AIPIIMapping__c storedMapping = recordByConversation.get(conversationId);
      Map<String, String> realToFake = new Map<String, String>();

      // [3] Read the saved pairs, dropping any pair with a blank fake value because there is nothing to restore it to
      if (
        storedMapping != null && String.isNotBlank(storedMapping.MappingJson__c)
      ) {
        Map<String, Object> stored = (Map<String, Object>) JSON.deserializeUntyped(
          storedMapping.MappingJson__c
        );

        for (String storedRealValue : stored.keySet()) {
          if (String.isNotBlank((String) stored.get(storedRealValue)))
            realToFake.put(
              storedRealValue,
              (String) stored.get(storedRealValue)
            );
        }
      }

      realToFakeByConversation.put(conversationId, realToFake);
    }

    // [4] Return the cached pairs
    return realToFakeByConversation.get(conversationId);
  }

  // The fake value already paired with a real value in this conversation, or null.
  public static String getFakeValue(Id conversationId, String realValue) {
    // [1] Nothing to look up
    if (conversationId == null || String.isBlank(realValue))
      return null;

    // [2] Return the fake value paired with the real value
    return getMapping(conversationId).get(realValue);
  }

  // The real value behind a fake value in this conversation, or null.
  public static String getRealValue(Id conversationId, String fakeValue) {
    // [1] Nothing to look up
    if (conversationId == null || String.isBlank(fakeValue))
      return null;

    // [2] Build the fake -> real lookup once, by inverting the real -> fake pairs
    if (!fakeToRealByConversation.containsKey(conversationId)) {
      Map<String, String> fakeToReal = new Map<String, String>();
      Map<String, String> realToFake = getMapping(conversationId);

      for (String mappedRealValue : realToFake.keySet())
        fakeToReal.put(realToFake.get(mappedRealValue), mappedRealValue);

      fakeToRealByConversation.put(conversationId, fakeToReal);
    }

    // [3] Return the real value behind the fake value
    return fakeToRealByConversation.get(conversationId).get(fakeValue);
  }

  // Adds one pairing. Returns false, changing nothing, when the real value is already paired or the write failed.
  public static Boolean addMapping(
    Id conversationId,
    String realValue,
    String fakeValue
  ) {
    // [1] Refuse anything that is not a conversation, or a blank value
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType ||
      String.isBlank(realValue) ||
      String.isBlank(fakeValue)
    )
      return false;

    // [2] Refuse a real value that is already paired, so the first fake value stays
    if (getMapping(conversationId).containsKey(realValue))
      return false;

    // [3] Load the conversation's AIPIIMapping__c once. System mode, because no permission set grants this object
    if (!recordByConversation.containsKey(conversationId)) {
      List<AIPIIMapping__c> existingMappings = [
        SELECT Id, MappingJson__c
        FROM AIPIIMapping__c
        WHERE AIConversation__c = :conversationId
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      recordByConversation.put(
        conversationId,
        existingMappings.isEmpty() ? null : existingMappings[0]
      );
    }

    // [4] Add the new pair to the record's JSON, creating the record when the conversation has none yet
    AIPIIMapping__c mappingRecord = recordByConversation.get(conversationId);
    Map<String, Object> pairs = mappingRecord != null &&
      String.isNotBlank(mappingRecord.MappingJson__c)
      ? (Map<String, Object>) JSON.deserializeUntyped(
          mappingRecord.MappingJson__c
        )
      : new Map<String, Object>();
    pairs.put(realValue, fakeValue);
    String updatedJson = JSON.serialize(pairs);

    if (mappingRecord == null)
      mappingRecord = new AIPIIMapping__c(AIConversation__c = conversationId);
    mappingRecord.MappingJson__c = updatedJson;
    recordByConversation.put(conversationId, mappingRecord);

    // [5] Hold the record while writes are deferred, otherwise save it now and log a failure
    if (isDeferringWrites) {
      unsavedConversationIds.add(conversationId);
    } else {
      Database.UpsertResult upsertResult = Database.upsert(
        mappingRecord,
        false,
        AccessLevel.SYSTEM_MODE
      );

      if (!upsertResult.isSuccess()) {
        AIPlatformLogManager.logCustomMessage(
          'A PII mapping could not be saved.',
          String.valueOf(upsertResult.getErrors()),
          'AIPiiMappingService',
          'addMapping',
          conversationId
        );
        return false;
      }
    }

    // [6] Keep the cache up to date, so a read straight after this reflects the new pair without another query
    getMapping(conversationId).put(realValue, fakeValue);

    if (!fakeToRealByConversation.containsKey(conversationId)) {
      Map<String, String> fakeToReal = new Map<String, String>();
      Map<String, String> realToFake = getMapping(conversationId);

      for (String mappedRealValue : realToFake.keySet())
        fakeToReal.put(realToFake.get(mappedRealValue), mappedRealValue);

      fakeToRealByConversation.put(conversationId, fakeToReal);
    }

    fakeToRealByConversation.get(conversationId).put(fakeValue, realValue);

    // [7] Report that the pair was added
    return true;
  }

  // Saves every pairing held while writes were deferred. Must run after the transaction's last callout.
  public static void saveCached() {
    // [1] Nothing held - nothing to save
    if (unsavedConversationIds.isEmpty())
      return;

    // [2] Collect the held records and clear the list
    List<AIPIIMapping__c> records = new List<AIPIIMapping__c>();

    for (Id conversationId : unsavedConversationIds)
      records.add(recordByConversation.get(conversationId));

    unsavedConversationIds.clear();

    // [3] Save them all in one pass
    List<Database.UpsertResult> upsertResults = Database.upsert(
      records,
      false,
      AccessLevel.SYSTEM_MODE
    );

    // [4] Log each pair that could not be saved
    for (Database.UpsertResult upsertResult : upsertResults) {
      if (!upsertResult.isSuccess())
        AIPlatformLogManager.logCustomMessage(
          'A PII mapping could not be saved.',
          String.valueOf(upsertResult.getErrors()),
          'AIPiiMappingService',
          'saveCached',
          null
        );
    }
  }
}
