/*
Class Name: AIPiiMappingService

=================================================================
=================================================================

Description: Remembers, per conversation, which fake value stands in for which real value, so
the model sees consistent stand-ins and its reply can be turned back into real values before
the user reads it. The pairs are stored as JSON in one AIPIIMapping__c per conversation.

Nobody is granted AIPIIMapping__c (it holds real values next to their fake ones), so this class
is the only reader and writer, and every query and write is explicit system mode. It is only
ever asked about a conversation the caller has already authorised.

Writes can be deferred. While a turn's tool-calling loop is running, a write would block the
next callout (uncommitted work), so the agent manager sets isDeferringWrites; pairs are then held
in memory and saveCached() writes them once, after the last callout.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt: explicit system mode on every statement, method names shortened (saveCached), single-use helpers inlined, failures reported through the log rather than swallowed.
*/

public inherited sharing class AIPiiMappingService {
  // Set before a callout loop that may mask PII between callouts, and cleared once the callouts are done.
  public static Boolean isDeferringWrites = false;

  private static Map<Id, Map<String, String>> realToFakeByConversation = new Map<Id, Map<String, String>>();
  private static Map<Id, Map<String, String>> fakeToRealByConversation = new Map<Id, Map<String, String>>();
  private static Map<Id, AIPIIMapping__c> recordByConversation = new Map<Id, AIPIIMapping__c>();
  private static Set<Id> unsavedConversationIds = new Set<Id>();

  // Real value -> fake value for the conversation. Empty for anything that is not a conversation.
  public static Map<String, String> getMapping(Id conversationId) {
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType
    )
      return new Map<String, String>();

    if (!realToFakeByConversation.containsKey(conversationId)) {
      // The conversation's AIPIIMapping__c, cached. System mode: no permission set grants this object.
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

      if (
        storedMapping != null && String.isNotBlank(storedMapping.MappingJson__c)
      ) {
        // A pair with a blank fake value has nothing to restore to, so it is dropped.
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

    return realToFakeByConversation.get(conversationId);
  }

  // The fake value already paired with a real value in this conversation, or null.
  public static String getFakeValue(Id conversationId, String realValue) {
    if (conversationId == null || String.isBlank(realValue))
      return null;

    return getMapping(conversationId).get(realValue);
  }

  // The real value behind a fake value in this conversation, or null.
  public static String getRealValue(Id conversationId, String fakeValue) {
    if (conversationId == null || String.isBlank(fakeValue))
      return null;

    // Fake -> real, built by inverting the forward mapping.
    if (!fakeToRealByConversation.containsKey(conversationId)) {
      Map<String, String> fakeToReal = new Map<String, String>();
      Map<String, String> realToFake = getMapping(conversationId);
      for (String mappedRealValue : realToFake.keySet())
        fakeToReal.put(realToFake.get(mappedRealValue), mappedRealValue);
      fakeToRealByConversation.put(conversationId, fakeToReal);
    }

    return fakeToRealByConversation.get(conversationId).get(fakeValue);
  }

  // Adds one pairing. Returns false, changing nothing, when the real value is already paired or the write failed.
  public static Boolean addMapping(
    Id conversationId,
    String realValue,
    String fakeValue
  ) {
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType ||
      String.isBlank(realValue) ||
      String.isBlank(fakeValue)
    )
      return false;
    if (getMapping(conversationId).containsKey(realValue))
      return false;

    // The conversation's AIPIIMapping__c, cached. System mode: no permission set grants this object.
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

    // The cache stays authoritative, so a read straight after this reflects it without another query.
    getMapping(conversationId).put(realValue, fakeValue);

    if (!fakeToRealByConversation.containsKey(conversationId)) {
      Map<String, String> fakeToReal = new Map<String, String>();
      Map<String, String> realToFake = getMapping(conversationId);
      for (String mappedRealValue : realToFake.keySet())
        fakeToReal.put(realToFake.get(mappedRealValue), mappedRealValue);
      fakeToRealByConversation.put(conversationId, fakeToReal);
    }

    fakeToRealByConversation.get(conversationId).put(fakeValue, realValue);

    return true;
  }

  // Saves every pairing held while writes were deferred. Must run after the transaction's last callout.
  public static void saveCached() {
    if (unsavedConversationIds.isEmpty())
      return;

    List<AIPIIMapping__c> records = new List<AIPIIMapping__c>();
    for (Id conversationId : unsavedConversationIds)
      records.add(recordByConversation.get(conversationId));
    unsavedConversationIds.clear();

    List<Database.UpsertResult> upsertResults = Database.upsert(
      records,
      false,
      AccessLevel.SYSTEM_MODE
    );

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
