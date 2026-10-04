/*
Class Name: AIAssistGlobalUtility

=================================================================
=================================================================

Description: Stamps the identifiers the object model asks the package to generate.

PublicId__c      A stable external identifier. Exists only on AIAgent__c and AIConversation__c
                 (docs/SECURITY_MODEL.md, "Identifier fields"). Set to a random UUID.
DeveloperName__c The unique, code-friendly External Id of configuration that moves between orgs:
                 AIAgent__c, AIDataSource__c, AIWorkflowAction__c, AIModelConfiguration__c and
                 AIPromptTemplate__c. Derived from Name when Name is text. A Data Source and a
                 Workflow Action have an auto-number Name, blank until after insert, so theirs is
                 derived from the required name field the admin fills in (SourceName__c,
                 ActionName__c).

Both methods act only on objects that actually have the field, found through describe, so they stay
correct when a field is added to or removed from an object. They never overwrite a value the
record already has.

Fields are resolved to describe tokens, not looked up by a hardcoded API name string: inside a
namespaced package the describe keys carry the namespace prefix, so a plain 'PublicId__c' lookup
would silently find nothing in a subscriber org.

Length and uniqueness are enforced here rather than left to fail on save: a derived DeveloperName is
cut to the field's length and, when it collides with an existing record or another record in the
same batch, gets a short random suffix. The unique setting on the field stays the backstop.

Failures are logged and the record is saved without the identifier; this class never blocks the DML
that called it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          UUID from System.Uuid instead of an MD5 digest, namespace-safe field resolution, describe cached per transaction, DeveloperName cut to the field length and made unique, derived from SourceName__c / ActionName__c where Name is an auto-number, single-use helpers inlined.
3.0          Chandler Stuart          The org's day: daily limits and the monthly reset follow the org's time zone.
*/

public inherited sharing class AIAssistGlobalUtility {
  private static final Integer SUFFIX_LENGTH = 6;

  // Where a Developer Name is derived from, in order: Name first, then the required text name of the objects whose Name is an auto-number.
  private static final List<String> DEVELOPER_NAME_SOURCE_FIELDS = new List<String>{
    'Name',
    'SourceName__c',
    'ActionName__c'
  };

  // What describe says about one identifier field on one object, cached for the transaction because a trigger can call this many times.
  private class IdentifierFieldDescription {
    Schema.SObjectField fieldToken;
    Integer maxLength;
  }

  private static Map<Schema.SObjectType, IdentifierFieldDescription> publicIdFieldByType = new Map<Schema.SObjectType, IdentifierFieldDescription>();
  private static Map<Schema.SObjectType, IdentifierFieldDescription> developerNameFieldByType = new Map<Schema.SObjectType, IdentifierFieldDescription>();
  private static Map<Schema.SObjectType, List<Schema.SObjectField>> sourceFieldsByType = new Map<Schema.SObjectType, List<Schema.SObjectField>>();

  // For a before-save check that could not run: refuses the save instead of letting an unchecked record through. A record saved with a blank unique key would allow duplicates, and one with an unchecked object name would fail later in front of a user. Null-safe.
  public static void refuseSave(List<SObject> records) {
    if (records == null)
      return;

    for (SObject record : records)
      record.addError(Label.AI_Error_Integrity_Check);
  }

  public static void generatePublicId(List<SObject> records) {
    try {
      if (records == null || records.isEmpty())
        return;

      for (SObject record : records) {
        if (record == null)
          continue;

        Schema.SObjectType recordType = record.getSObjectType();

        // The identifier field on this object, or a description with a null token when the object does not have it. The package stamps as itself, so the running user's field-level access is irrelevant. The key is the plain name, or the same name behind a namespace prefix (namespace__Field__c); only the match is described.
        if (!publicIdFieldByType.containsKey(recordType)) {
          IdentifierFieldDescription publicIdDescription = new IdentifierFieldDescription();
          Map<String, Schema.SObjectField> recordFieldsByName = recordType.getDescribe(
              SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
          String wantedFieldName = AIAssistApplicationConstants.PUBLIC_ID_FIELD_API_NAME.toLowerCase();
          for (String fieldKey : recordFieldsByName.keySet()) {
            if (
              fieldKey == wantedFieldName ||
              fieldKey.endsWith('__' + wantedFieldName)
            ) {
              publicIdDescription.fieldToken = recordFieldsByName.get(fieldKey);
              break;
            }
          }
          publicIdDescription.maxLength = publicIdDescription.fieldToken == null
            ? 0
            : publicIdDescription.fieldToken.getDescribe().getLength();
          publicIdFieldByType.put(recordType, publicIdDescription);
        }

        IdentifierFieldDescription publicIdField = publicIdFieldByType.get(
          recordType
        );

        if (
          publicIdField.fieldToken == null ||
          record.get(publicIdField.fieldToken) != null
        )
          continue; // No such field on this object, or already populated.

        String publicId = System.Uuid.randomUUID().toString();

        // A field narrower than a UUID still gets a collision-safe value: without hyphens a UUID is 32 characters. Anything narrower cannot hold one safely.
        if (publicId.length() > publicIdField.maxLength)
          publicId = publicId.remove('-');

        if (publicId.length() > publicIdField.maxLength) {
          AIPlatformLogManager.logCustomMessage(
            'PublicId__c on ' +
              recordType +
              ' is ' +
              publicIdField.maxLength +
              ' characters, too short for a UUID. No Public Id was set.',
            null,
            'AIAssistGlobalUtility',
            'generatePublicId',
            null
          );
          continue;
        }

        record.put(publicIdField.fieldToken, publicId);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAssistGlobalUtility',
        'generatePublicId'
      );
    }
  }

  public static void generateDeveloperName(List<SObject> records) {
    try {
      if (records == null || records.isEmpty())
        return;

      // Candidates by object type, so uniqueness is checked once per type rather than once per record.
      Map<Schema.SObjectType, List<SObject>> recordsNeedingName = new Map<Schema.SObjectType, List<SObject>>();
      Map<Schema.SObjectType, List<String>> baseNamesByType = new Map<Schema.SObjectType, List<String>>(); // Parallel to the records above. Not keyed by record: two new records with the same Name are equal as SObjects.
      Map<Schema.SObjectType, Set<String>> lowerCaseNamesByType = new Map<Schema.SObjectType, Set<String>>();

      for (SObject record : records) {
        if (record == null)
          continue;

        Schema.SObjectType sObjectType = record.getSObjectType();

        // The Developer Name field on this object, or a description with a null token when the object does not have it. Same lookup as the Public Id field above.
        if (!developerNameFieldByType.containsKey(sObjectType)) {
          IdentifierFieldDescription developerNameDescription = new IdentifierFieldDescription();
          Map<String, Schema.SObjectField> objectFieldsByName = sObjectType.getDescribe(
              SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
          String wantedDeveloperNameField = AIAssistApplicationConstants.DEVELOPER_NAME_FIELD_API_NAME.toLowerCase();
          for (String objectFieldKey : objectFieldsByName.keySet()) {
            if (
              objectFieldKey == wantedDeveloperNameField ||
              objectFieldKey.endsWith('__' + wantedDeveloperNameField)
            ) {
              developerNameDescription.fieldToken = objectFieldsByName.get(
                objectFieldKey
              );
              break;
            }
          }
          developerNameDescription.maxLength = developerNameDescription.fieldToken ==
            null
            ? 0
            : developerNameDescription.fieldToken.getDescribe().getLength();
          developerNameFieldByType.put(sObjectType, developerNameDescription);
        }

        IdentifierFieldDescription developerNameField = developerNameFieldByType.get(
          sObjectType
        );

        if (
          developerNameField.fieldToken == null ||
          record.get(developerNameField.fieldToken) != null
        )
          continue; // No such field on this object, or already populated.

        if (!sourceFieldsByType.containsKey(sObjectType)) {
          List<Schema.SObjectField> sourceFields = new List<Schema.SObjectField>();
          for (String sourceFieldName : DEVELOPER_NAME_SOURCE_FIELDS) {
            Map<String, Schema.SObjectField> sourceCandidatesByName = sObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
              )
              .fields.getMap();
            String wantedSourceField = sourceFieldName.toLowerCase();
            for (String candidateKey : sourceCandidatesByName.keySet()) {
              if (
                candidateKey == wantedSourceField ||
                candidateKey.endsWith('__' + wantedSourceField)
              ) {
                sourceFields.add(sourceCandidatesByName.get(candidateKey));
                break;
              }
            }
          }
          sourceFieldsByType.put(sObjectType, sourceFields);
        }

        // The first source field with text in it. An auto-number Name is blank until after insert, so the next source field is tried.
        String sourceText = null;
        for (
          Schema.SObjectField textSourceField : sourceFieldsByType.get(
            sObjectType
          )
        ) {
          Object fieldValue = record.get(textSourceField);
          if (
            fieldValue != null && String.isNotBlank(String.valueOf(fieldValue))
          ) {
            sourceText = String.valueOf(fieldValue);
            break;
          }
        }

        if (sourceText == null)
          continue; // Nothing to derive from yet.

        // Letters, numbers and single underscores, never empty, cut to leave room for a suffix so a collision never produces a value longer than the field. A name of characters that cannot be kept (non-Latin script) still gets a usable value.
        String baseName = sourceText.trim()
          .replaceAll('[^a-zA-Z0-9]+', '_')
          .replaceAll('^_+|_+$', '');
        if (String.isBlank(baseName))
          baseName =
            'Record_' +
            System.Uuid.randomUUID().toString().remove('-').left(SUFFIX_LENGTH);

        Integer maxBaseLength = Math.max(
          1,
          developerNameField.maxLength - SUFFIX_LENGTH - 1
        );
        if (baseName.length() > maxBaseLength)
          baseName = baseName.left(maxBaseLength).replaceAll('_+$', '');

        if (!recordsNeedingName.containsKey(sObjectType)) {
          recordsNeedingName.put(sObjectType, new List<SObject>());
          baseNamesByType.put(sObjectType, new List<String>());
          lowerCaseNamesByType.put(sObjectType, new Set<String>());
        }

        recordsNeedingName.get(sObjectType).add(record);
        baseNamesByType.get(sObjectType).add(baseName);
        lowerCaseNamesByType.get(sObjectType).add(baseName.toLowerCase());
      }

      for (Schema.SObjectType sObjectType : recordsNeedingName.keySet()) {
        Schema.SObjectField nameField = developerNameFieldByType.get(
            sObjectType
          )
          .fieldToken;

        // Case-insensitive, like the unique setting on the field.
        Set<String> takenLowerCase = new UniquenessLookup()
          .findExisting(
            sObjectType,
            nameField,
            lowerCaseNamesByType.get(sObjectType)
          );

        for (
          Integer recordIndex = 0;
          recordIndex < recordsNeedingName.get(sObjectType).size();
          recordIndex++
        ) {
          String candidate = baseNamesByType.get(sObjectType)[recordIndex];
          if (takenLowerCase.contains(candidate.toLowerCase()))
            candidate =
              candidate +
              '_' +
              System.Uuid.randomUUID()
                .toString()
                .remove('-')
                .left(SUFFIX_LENGTH);

          recordsNeedingName.get(sObjectType)[recordIndex]
            .put(nameField, candidate);
          takenLowerCase.add(candidate.toLowerCase()); // A later record in this batch with the same name now sees it as taken.
        }
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAssistGlobalUtility',
        'generateDeveloperName'
      );
    }
  }

  // Reads existing Developer Names across ALL records of the object, whatever the running user can see: the unique setting is global, so a check limited to the user's visible records would let a collision through and fail the save. Object and field names come from describe, never from input, and the names looked up are bound.
  private without sharing class UniquenessLookup {
    public Set<String> findExisting(
      Schema.SObjectType sObjectType,
      Schema.SObjectField nameField,
      Set<String> lowerCaseNames
    ) {
      Set<String> existingNames = new Set<String>();
      String fieldName = nameField.getDescribe().getName();

      for (
        SObject record : Database.queryWithBinds(
          'SELECT ' +
            fieldName +
            ' FROM ' +
            sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE ' +
            fieldName +
            ' IN :lowerCaseNames',
          new Map<String, Object>{ 'lowerCaseNames' => lowerCaseNames },
          AccessLevel.SYSTEM_MODE
        )
      ) {
        existingNames.add(String.valueOf(record.get(nameField)).toLowerCase());
      }

      return existingNames;
    }
  }

  // =============================================================
  // The org's day
  // =============================================================

  // Daily limits and the monthly reset follow the org's own time zone (Company Information), not UTC and not the time zone of whichever user sends a message: everyone in the org shares one day. Read once per transaction.
  @TestVisible
  private static String orgTimeZoneSidKey;
  // A test cannot move the clock.
  @TestVisible
  private static Datetime nowForTest;

  public static TimeZone getOrgTimeZone() {
    if (orgTimeZoneSidKey == null)
      orgTimeZoneSidKey = [
        SELECT TimeZoneSidKey
        FROM Organization
        WITH SYSTEM_MODE
        LIMIT 1
      ]
      .TimeZoneSidKey;

    return TimeZone.getTimeZone(orgTimeZoneSidKey);
  }

  // The calendar date a moment falls on in the org's time zone.
  public static Date getOrgDate(Datetime moment) {
    return Date.valueOf(moment.format('yyyy-MM-dd', getOrgTimeZone().getID()));
  }

  // Today in the org's time zone: the day usage is counted against.
  public static Date getOrgToday() {
    return getOrgDate(nowForTest == null ? System.now() : nowForTest);
  }

  // The moment the org's next day starts, which is when daily limits reset.
  public static Datetime getNextOrgMidnight() {
    Date tomorrow = getOrgToday().addDays(1);
    Datetime asIfUtc = Datetime.newInstanceGmt(
      tomorrow,
      Time.newInstance(0, 0, 0, 0)
    );

    return asIfUtc.addSeconds(-getOrgTimeZone().getOffset(asIfUtc) / 1000);
  }
}
