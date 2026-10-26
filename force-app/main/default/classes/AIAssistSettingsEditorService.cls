/*
Class Name: AIAssistSettingsEditorService

=================================================================
=================================================================

Description: Reads and saves the settings the Settings tab edits: AI Assist Settings and AI Assist UI Settings.

Step 1: Refuse anyone without the Manage Settings custom permission
Step 2: Read every row of both settings, with the organisation row first, for the tab to show
Step 3: Save one row at organisation, profile or user level after checking each value, then clear the cached settings
Step 4: Delete a profile or user row, never the organisation row
Step 5: Find the profiles and users an admin can create a row for

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistSettingsEditorService {

    public class AIAssistSettingsEditorServiceException extends Exception {}

    // Every field the tab may read or write, by the name the tab uses. Anything not listed here is refused.
    private static final Map<String, Schema.SObjectField> ASSIST_FIELDS = new Map<String, Schema.SObjectField>{
        'IsEnabled__c' => AIAssistSettings__c.IsEnabled__c,
        'MaxMessageLength__c' => AIAssistSettings__c.MaxMessageLength__c,
        'MaxMessagesPerUserPerMinute__c' => AIAssistSettings__c.MaxMessagesPerUserPerMinute__c,
        'MaxMessagesInFlight__c' => AIAssistSettings__c.MaxMessagesInFlight__c,
        'ProcessingLockSeconds__c' => AIAssistSettings__c.ProcessingLockSeconds__c,
        'CalloutTimeoutMilliseconds__c' => AIAssistSettings__c.CalloutTimeoutMilliseconds__c,
        'RetryAttempts__c' => AIAssistSettings__c.RetryAttempts__c,
        'RetryableStatusCodes__c' => AIAssistSettings__c.RetryableStatusCodes__c,
        'AIProviderSuccessStatusCodes__c' => AIAssistSettings__c.AIProviderSuccessStatusCodes__c,
        'DefaultMaxToolCallingIterations__c' => AIAssistSettings__c.DefaultMaxToolCallingIterations__c,
        'MaxToolCallingIterationsCap__c' => AIAssistSettings__c.MaxToolCallingIterationsCap__c,
        'MaxToolCallsPerIteration__c' => AIAssistSettings__c.MaxToolCallsPerIteration__c,
        'CurrentTermsVersion__c' => AIAssistSettings__c.CurrentTermsVersion__c,
        'AIUsagePolicyUrl__c' => AIAssistSettings__c.AIUsagePolicyUrl__c,
        'MaxPIIRegistryObjects__c' => AIAssistSettings__c.MaxPIIRegistryObjects__c
    };

    private static final Map<String, Schema.SObjectField> UI_FIELDS = new Map<String, Schema.SObjectField>{
        'IsEnabled__c' => AIAssistUISettings__c.IsEnabled__c,
        'IsMaintenanceMode__c' => AIAssistUISettings__c.IsMaintenanceMode__c,
        'IsFeedbackEnabled__c' => AIAssistUISettings__c.IsFeedbackEnabled__c,
        'TypingIndicatorEnabled__c' => AIAssistUISettings__c.TypingIndicatorEnabled__c,
        'ShouldShowExecutionTrace__c' => AIAssistUISettings__c.ShouldShowExecutionTrace__c,
        'ShowTimestampOnMessages__c' => AIAssistUISettings__c.ShowTimestampOnMessages__c,
        'IsWorkflowActionsEnabled__c' => AIAssistUISettings__c.IsWorkflowActionsEnabled__c,
        'IsInlineWorkflowActionsEnabled__c' => AIAssistUISettings__c.IsInlineWorkflowActionsEnabled__c,
        'SuggestedActionsDisplay__c' => AIAssistUISettings__c.SuggestedActionsDisplay__c,
        'MaxVisibleMessageHistory__c' => AIAssistUISettings__c.MaxVisibleMessageHistory__c
    };

    // The only AI Assist Settings fields a profile or user row may hold. The rest are about the whole org.
    private static final Set<String> OVERRIDABLE_ASSIST_FIELDS = new Set<String>{'MaxMessageLength__c', 'MaxMessagesPerUserPerMinute__c', 'DefaultMaxToolCallingIterations__c', 'MaxToolCallingIterationsCap__c', 'MaxToolCallsPerIteration__c'};

    // Fields that cannot be blank on the organisation row. On a profile or user row only the tool-calling numbers must be filled in, because the row replaces the organisation values for them.
    private static final Set<String> REQUIRED_ASSIST_FIELDS = new Set<String>{'ProcessingLockSeconds__c', 'CalloutTimeoutMilliseconds__c', 'RetryAttempts__c', 'DefaultMaxToolCallingIterations__c', 'MaxToolCallingIterationsCap__c', 'MaxToolCallsPerIteration__c', 'AIProviderSuccessStatusCodes__c'};
    private static final Set<String> REQUIRED_OVERRIDE_FIELDS = new Set<String>{'DefaultMaxToolCallingIterations__c', 'MaxToolCallingIterationsCap__c', 'MaxToolCallsPerIteration__c'};

    // The smallest and largest whole number each number field accepts.
    private static final Map<String, List<Integer>> NUMBER_RANGES = new Map<String, List<Integer>>{
        'MaxMessageLength__c' => new List<Integer>{1, 99999},
        'MaxMessagesPerUserPerMinute__c' => new List<Integer>{1, 999},
        'MaxMessagesInFlight__c' => new List<Integer>{1, 9999},
        'ProcessingLockSeconds__c' => new List<Integer>{30, 3600},
        'CalloutTimeoutMilliseconds__c' => new List<Integer>{AIAssistApplicationConstants.ANTHROPIC_AGENT_MIN_CALLOUT_MILLISECONDS, AIAssistApplicationConstants.ANTHROPIC_AGENT_MAX_CALLOUT_MILLISECONDS},
        'RetryAttempts__c' => new List<Integer>{0, 5},
        'DefaultMaxToolCallingIterations__c' => new List<Integer>{1, 50},
        'MaxToolCallingIterationsCap__c' => new List<Integer>{1, 50},
        'MaxToolCallsPerIteration__c' => new List<Integer>{1, 20},
        'MaxPIIRegistryObjects__c' => new List<Integer>{1, AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN},
        'MaxVisibleMessageHistory__c' => new List<Integer>{1, 200}
    };

    private static final Set<String> STATUS_CODE_FIELDS = new Set<String>{'RetryableStatusCodes__c', 'AIProviderSuccessStatusCodes__c'};
    private static final Integer MIN_STATUS_CODE = 100;
    private static final Integer MAX_STATUS_CODE = 599;

    // Reads every row of both settings for the tab. The organisation row is always first.
    public static AIAssistSettingsDataStructure.SettingsPage getSettingsPage() {

        // [1] Refuse a user who may not use the Settings tab
        requireManager();

        // [2] Read the rows of each settings object
        AIAssistSettingsDataStructure.SettingsPage page = new AIAssistSettingsDataStructure.SettingsPage();
        page.assistRows = getRows(AIAssistApplicationConstants.SETTINGS_NAME_ASSIST);
        page.uiRows = getRows(AIAssistApplicationConstants.SETTINGS_NAME_UI);

        return page;
    }

    // Saves one row, creating it if the profile or user has none, and returns it as saved.
    public static AIAssistSettingsDataStructure.SettingsRow saveRow(String settingsName, String scope, Id ownerId, Map<String, Object> values) {

        // [1] Refuse a user who may not use the Settings tab, and a name or scope the tab never sends
        requireManager();
        Map<String, Schema.SObjectField> fieldTokens = getFieldTokens(settingsName);
        Id rowOwnerId = getRowOwnerId(scope, ownerId);
        Boolean isOrganisationRow = scope == AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION;
        Boolean isAssist = settingsName == AIAssistApplicationConstants.SETTINGS_NAME_ASSIST;

        // [2] Refuse a field the tab may not change on this row
        Map<String, Object> newValues = values == null ? new Map<String, Object>() : values;

        for (String fieldName : newValues.keySet()) {

            Boolean isKnown = fieldTokens.containsKey(fieldName);
            Boolean isAllowedHere = !isAssist || isOrganisationRow || OVERRIDABLE_ASSIST_FIELDS.contains(fieldName);
            if (!isKnown || !isAllowedHere) throw new AIAssistSettingsEditorServiceException(String.format(Label.AI_Settings_Error_Field_Not_Allowed, new List<String>{fieldName}));
        }

        // [3] Find the row to change, or start a new one from the field defaults
        SObject record = findRecord(settingsName, rowOwnerId);

        if (record == null) {

            record = buildDefaultRecord(settingsName);
            record.put('SetupOwnerId', rowOwnerId);
        }

        // [4] Put each value on the row
        for (String fieldName : newValues.keySet()) {

            setValue(record, fieldName, fieldTokens.get(fieldName), newValues.get(fieldName));
        }

        // [5] Check the row as it will be saved
        validateRecord(settingsName, isOrganisationRow, record);

        // [6] Save it, then drop the cached settings so the next read sees the change
        if (record.Id == null) Database.insert(record, AccessLevel.SYSTEM_MODE);
        else Database.update(record, AccessLevel.SYSTEM_MODE);

        AIAssistSettingsService.clearCache();

        // [7] Return the row as saved
        return buildRow(record, scope, rowOwnerId, getOwnerName(scope, rowOwnerId), fieldTokens);
    }

    // Deletes a profile or user row, which puts that profile or user back on the organisation values.
    public static void deleteRow(String settingsName, Id rowId) {

        // [1] Refuse a user who may not use the Settings tab
        requireManager();
        Map<String, Schema.SObjectField> fieldTokens = getFieldTokens(settingsName);

        // [2] Find the row
        String objectName = getObjectName(settingsName);
        List<SObject> records = Database.query('SELECT Id, SetupOwnerId FROM ' + String.escapeSingleQuotes(objectName) + ' WHERE Id = :rowId LIMIT 1', AccessLevel.SYSTEM_MODE);
        if (records.isEmpty()) throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Row_Not_Found);

        // [3] Refuse to delete the organisation row
        Id ownerId = (Id) records[0].get('SetupOwnerId');
        if (ownerId.getSobjectType() == Schema.Organization.SObjectType) throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Org_Row_Delete);

        // [4] Delete it and drop the cached settings
        Database.delete(records, AccessLevel.SYSTEM_MODE);
        AIAssistSettingsService.clearCache();
    }

    // Finds the profiles or users whose name matches the text, for a new profile or user row.
    public static List<AIAssistSettingsDataStructure.OwnerOption> findOwners(String scope, String searchText) {

        // [1] Refuse a user who may not use the Settings tab
        requireManager();
        List<AIAssistSettingsDataStructure.OwnerOption> options = new List<AIAssistSettingsDataStructure.OwnerOption>();

        // [2] Wait for enough text to make the search worth running
        String trimmedText = String.isBlank(searchText) ? '' : searchText.trim();
        if (trimmedText.length() < AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MIN_LENGTH) return options;

        String likeText = '%' + String.escapeSingleQuotes(trimmedText) + '%';
        Integer maxResults = AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MAX_RESULTS;

        // [3] Search profiles or users
        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE) {

            for (Profile matchingProfile : [SELECT Id, Name FROM Profile WHERE Name LIKE :likeText WITH SYSTEM_MODE ORDER BY Name LIMIT :maxResults]) {

                options.add(buildOwnerOption(matchingProfile.Id, matchingProfile.Name, null));
            }

        } else if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_USER) {

            for (User matchingUser : [SELECT Id, Name, Username FROM User WHERE IsActive = TRUE AND UserType = :AIAssistApplicationConstants.USER_TYPE_STANDARD AND (Name LIKE :likeText OR Username LIKE :likeText) WITH SYSTEM_MODE ORDER BY Name LIMIT :maxResults]) {

                options.add(buildOwnerOption(matchingUser.Id, matchingUser.Name, matchingUser.Username));
            }

        } else {

            throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Owner);
        }

        return options;
    }

    // Refuses a user who does not hold the Manage Settings custom permission.
    public static void requireManager() {

        // [1] Check the custom permission, which the Admin and Super User permission sets grant
        if (!FeatureManagement.checkPermission(AIAssistApplicationConstants.PERMISSION_MANAGE_SETTINGS)) throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Access);
    }

    // Refuses a picklist value that the field does not list.
    public static void validateChoice(SObject record, String fieldName, Schema.SObjectField fieldToken) {

        // [1] Only the choice fields need checking
        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        Boolean isChoiceField = fieldDescribe.getType() == Schema.DisplayType.PICKLIST || fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST;
        Object fieldValue = record.get(fieldToken);
        if (!isChoiceField || fieldValue == null || String.isBlank((String) fieldValue)) return;

        // [2] Collect the values the field lists
        Set<String> allowedValues = new Set<String>();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {

            if (entry.isActive()) allowedValues.add(entry.getValue());
        }

        // [3] Every chosen value must be listed
        for (String chosenValue : ((String) fieldValue).split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR)) {

            if (!allowedValues.contains(chosenValue)) throw new AIAssistSettingsEditorServiceException(String.format(Label.AI_Settings_Error_Choice, new List<String>{fieldDescribe.getLabel()}));
        }
    }

    // The fields of the named settings object, and a refusal for any other name.
    private static Map<String, Schema.SObjectField> getFieldTokens(String settingsName) {

        // [1] Pick the field list for the settings the tab named
        if (settingsName == AIAssistApplicationConstants.SETTINGS_NAME_ASSIST) return ASSIST_FIELDS;
        if (settingsName == AIAssistApplicationConstants.SETTINGS_NAME_UI) return UI_FIELDS;

        throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Settings_Name);
    }

    // The API name of the named settings object, including any namespace.
    private static String getObjectName(String settingsName) {

        // [1] Describe the object to get its full name
        Boolean isAssist = settingsName == AIAssistApplicationConstants.SETTINGS_NAME_ASSIST;
        Schema.SObjectType objectType = isAssist ? AIAssistSettings__c.SObjectType : AIAssistUISettings__c.SObjectType;

        return objectType.getDescribe().getName();
    }

    // The Id a row is saved against: the organisation, or a profile or user the admin picked.
    private static Id getRowOwnerId(String scope, Id ownerId) {

        // [1] The organisation row belongs to the organisation
        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION) return (Id) UserInfo.getOrganizationId();

        // [2] A profile row needs a profile, and a user row needs a user
        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE && ownerId != null && ownerId.getSobjectType() == Schema.Profile.SObjectType) return ownerId;
        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_USER && ownerId != null && ownerId.getSobjectType() == Schema.User.SObjectType) return ownerId;

        throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Owner);
    }

    // A new row holding the field defaults, so the default-on switches do not read as off.
    private static SObject buildDefaultRecord(String settingsName) {

        // [1] Create the row from the field defaults
        Boolean isAssist = settingsName == AIAssistApplicationConstants.SETTINGS_NAME_ASSIST;
        Schema.SObjectType objectType = isAssist ? AIAssistSettings__c.SObjectType : AIAssistUISettings__c.SObjectType;

        return objectType.newSObject(null, true);
    }

    // The saved row for an owner, or null when there is none.
    private static SObject findRecord(String settingsName, Id ownerId) {

        // [1] Read the row and every field the tab edits
        Map<String, Schema.SObjectField> fieldTokens = getFieldTokens(settingsName);
        String query = 'SELECT Id, SetupOwnerId, ' + String.escapeSingleQuotes(String.join(getFieldNames(fieldTokens), ', ')) + ' FROM ' + String.escapeSingleQuotes(getObjectName(settingsName)) + ' WHERE SetupOwnerId = :ownerId LIMIT 1';
        List<SObject> records = Database.query(query, AccessLevel.SYSTEM_MODE);

        return records.isEmpty() ? null : records[0];
    }

    // The full API names of the fields, for a query.
    private static List<String> getFieldNames(Map<String, Schema.SObjectField> fieldTokens) {

        // [1] Describe each field to get its full name
        List<String> fieldNames = new List<String>();

        for (Schema.SObjectField fieldToken : fieldTokens.values()) {

            fieldNames.add(fieldToken.getDescribe().getName());
        }

        return fieldNames;
    }

    // Every row of one settings object: the organisation row first, then profile rows and user rows by name.
    private static List<AIAssistSettingsDataStructure.SettingsRow> getRows(String settingsName) {

        // [1] Read every saved row
        Map<String, Schema.SObjectField> fieldTokens = getFieldTokens(settingsName);
        String query = 'SELECT Id, SetupOwnerId, ' + String.escapeSingleQuotes(String.join(getFieldNames(fieldTokens), ', ')) + ' FROM ' + String.escapeSingleQuotes(getObjectName(settingsName)) + ' LIMIT 2000';
        List<SObject> records = Database.query(query, AccessLevel.SYSTEM_MODE);

        // [2] Sort them into the organisation row, profile rows and user rows
        SObject organisationRecord = null;
        Map<Id, SObject> profileRecords = new Map<Id, SObject>();
        Map<Id, SObject> userRecords = new Map<Id, SObject>();

        for (SObject record : records) {

            Id ownerId = (Id) record.get('SetupOwnerId');
            Schema.SObjectType ownerType = ownerId.getSobjectType();

            if (ownerType == Schema.Profile.SObjectType) profileRecords.put(ownerId, record);
            else if (ownerType == Schema.User.SObjectType) userRecords.put(ownerId, record);
            else organisationRecord = record;
        }

        // [3] The organisation row comes first, from the field defaults when it has never been saved
        List<AIAssistSettingsDataStructure.SettingsRow> rows = new List<AIAssistSettingsDataStructure.SettingsRow>();
        if (organisationRecord == null) organisationRecord = buildDefaultRecord(settingsName);
        rows.add(buildRow(organisationRecord, AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION, (Id) UserInfo.getOrganizationId(), UserInfo.getOrganizationName(), fieldTokens));

        // [4] Then the profile rows and the user rows, each by name
        rows.addAll(buildNamedRows(profileRecords, AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE, fieldTokens));
        rows.addAll(buildNamedRows(userRecords, AIAssistApplicationConstants.SETTINGS_SCOPE_USER, fieldTokens));

        return rows;
    }

    // Builds rows for profile or user records, sorted by the profile or user name.
    private static List<AIAssistSettingsDataStructure.SettingsRow> buildNamedRows(Map<Id, SObject> recordsByOwnerId, String scope, Map<String, Schema.SObjectField> fieldTokens) {

        // [1] Look up each owner's name
        Map<Id, String> namesByOwnerId = new Map<Id, String>();

        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE) {

            for (Profile ownerProfile : [SELECT Id, Name FROM Profile WHERE Id IN :recordsByOwnerId.keySet() WITH SYSTEM_MODE]) {

                namesByOwnerId.put(ownerProfile.Id, ownerProfile.Name);
            }

        } else {

            for (User ownerUser : [SELECT Id, Name FROM User WHERE Id IN :recordsByOwnerId.keySet() WITH SYSTEM_MODE]) {

                namesByOwnerId.put(ownerUser.Id, ownerUser.Name);
            }
        }

        // [2] Build a row for each, keyed by name then Id so the sort is stable
        Map<String, AIAssistSettingsDataStructure.SettingsRow> rowsBySortKey = new Map<String, AIAssistSettingsDataStructure.SettingsRow>();

        for (Id ownerId : recordsByOwnerId.keySet()) {

            String ownerName = namesByOwnerId.containsKey(ownerId) ? namesByOwnerId.get(ownerId) : String.valueOf(ownerId);
            rowsBySortKey.put(ownerName.toLowerCase() + '|' + ownerId, buildRow(recordsByOwnerId.get(ownerId), scope, ownerId, ownerName, fieldTokens));
        }

        // [3] Return them in name order
        List<String> sortKeys = new List<String>(rowsBySortKey.keySet());
        sortKeys.sort();

        List<AIAssistSettingsDataStructure.SettingsRow> rows = new List<AIAssistSettingsDataStructure.SettingsRow>();
        for (String sortKey : sortKeys) {

            rows.add(rowsBySortKey.get(sortKey));
        }

        return rows;
    }

    // Builds one row for the tab from a saved record.
    private static AIAssistSettingsDataStructure.SettingsRow buildRow(SObject record, String scope, Id ownerId, String ownerName, Map<String, Schema.SObjectField> fieldTokens) {

        // [1] Copy the identity of the row
        AIAssistSettingsDataStructure.SettingsRow row = new AIAssistSettingsDataStructure.SettingsRow();
        row.rowId = record.Id;
        row.scope = scope;
        row.ownerId = ownerId;
        row.ownerName = ownerName;

        // [2] Copy each field value by the name the tab uses
        for (String fieldName : fieldTokens.keySet()) {

            row.values.put(fieldName, record.get(fieldTokens.get(fieldName)));
        }

        return row;
    }

    // Builds a profile or user the admin can pick.
    private static AIAssistSettingsDataStructure.OwnerOption buildOwnerOption(Id ownerId, String name, String detail) {

        // [1] Copy the values
        AIAssistSettingsDataStructure.OwnerOption option = new AIAssistSettingsDataStructure.OwnerOption();
        option.ownerId = ownerId;
        option.name = name;
        option.detail = detail;

        return option;
    }

    // The name of the organisation, a profile or a user.
    private static String getOwnerName(String scope, Id ownerId) {

        // [1] The organisation
        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_ORGANISATION) return UserInfo.getOrganizationName();

        // [2] A profile
        if (scope == AIAssistApplicationConstants.SETTINGS_SCOPE_PROFILE) {

            List<Profile> profiles = [SELECT Name FROM Profile WHERE Id = :ownerId WITH SYSTEM_MODE LIMIT 1];
            return profiles.isEmpty() ? String.valueOf(ownerId) : profiles[0].Name;
        }

        // [3] Otherwise a user
        List<User> users = [SELECT Name FROM User WHERE Id = :ownerId WITH SYSTEM_MODE LIMIT 1];
        return users.isEmpty() ? String.valueOf(ownerId) : users[0].Name;
    }

    // Puts one value from the tab on a record, turning it into the type the field holds.
    private static void setValue(SObject record, String fieldName, Schema.SObjectField fieldToken, Object rawValue) {

        // [1] Work out the type of the field and a readable label for any message
        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        Schema.DisplayType fieldType = fieldDescribe.getType();
        String fieldLabel = fieldDescribe.getLabel();
        Boolean isBlank = rawValue == null || (rawValue instanceof String && String.isBlank((String) rawValue));

        // [2] A checkbox is never blank
        if (fieldType == Schema.DisplayType.BOOLEAN) {

            record.put(fieldToken, rawValue instanceof Boolean && (Boolean) rawValue);
            return;
        }

        // [3] A blank value clears the field
        if (isBlank) {

            record.put(fieldToken, null);
            return;
        }

        // [4] A number must be a whole number
        if (fieldType == Schema.DisplayType.DOUBLE || fieldType == Schema.DisplayType.INTEGER || fieldType == Schema.DisplayType.PERCENT || fieldType == Schema.DisplayType.CURRENCY) {

            Decimal numberValue = parseWholeNumber(fieldName, fieldLabel, rawValue);
            record.put(fieldToken, numberValue);
            return;
        }

        // [5] A multi-select list arrives as a list and is saved as text split by semicolons
        if (fieldType == Schema.DisplayType.MULTIPICKLIST) {

            List<String> choices = new List<String>();

            if (rawValue instanceof List<Object>) {

                for (Object choice : (List<Object>) rawValue) {

                    choices.add(String.valueOf(choice));
                }

            } else {

                choices.addAll(String.valueOf(rawValue).split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR));
            }

            record.put(fieldToken, String.join(choices, AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR));
            return;
        }

        // [6] Everything else is text, with a status code list tidied to digits and commas
        String textValue = String.valueOf(rawValue).trim();
        if (STATUS_CODE_FIELDS.contains(fieldName)) textValue = textValue.deleteWhitespace();

        record.put(fieldToken, textValue);
    }

    // Turns a value from the tab into a whole number, or refuses it with the allowed range.
    private static Decimal parseWholeNumber(String fieldName, String fieldLabel, Object rawValue) {

        // [1] Read the value as a number
        Decimal numberValue;

        try {

            numberValue = Decimal.valueOf(String.valueOf(rawValue));

        } catch (Exception ex) {

            throw new AIAssistSettingsEditorServiceException(buildRangeMessage(fieldName, fieldLabel));
        }

        // [2] A decimal part is refused
        if (numberValue != numberValue.setScale(0)) throw new AIAssistSettingsEditorServiceException(buildRangeMessage(fieldName, fieldLabel));

        return numberValue;
    }

    // The message for a number outside its range.
    private static String buildRangeMessage(String fieldName, String fieldLabel) {

        // [1] Use the range for the field, or a general whole number message when it has none
        List<Integer> range = NUMBER_RANGES.get(fieldName);
        if (range == null) return String.format(Label.AI_Settings_Error_Whole_Number_Range, new List<String>{fieldLabel, '0', '99999'});

        return String.format(Label.AI_Settings_Error_Whole_Number_Range, new List<String>{fieldLabel, String.valueOf(range[0]), String.valueOf(range[1])});
    }

    // Checks the row as it will be saved and refuses it with a plain message when a value is not allowed.
    private static void validateRecord(String settingsName, Boolean isOrganisationRow, SObject record) {

        // [1] Check each field the tab edits for this row
        Boolean isAssist = settingsName == AIAssistApplicationConstants.SETTINGS_NAME_ASSIST;
        Map<String, Schema.SObjectField> fieldTokens = getFieldTokens(settingsName);

        for (String fieldName : fieldTokens.keySet()) {

            if (isAssist && !isOrganisationRow && !OVERRIDABLE_ASSIST_FIELDS.contains(fieldName)) continue;

            Schema.SObjectField fieldToken = fieldTokens.get(fieldName);
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            Object fieldValue = record.get(fieldToken);
            Boolean isBlank = fieldValue == null || (fieldValue instanceof String && String.isBlank((String) fieldValue));

            // [2] A required field must be filled in
            Set<String> requiredFields = isOrganisationRow ? REQUIRED_ASSIST_FIELDS : REQUIRED_OVERRIDE_FIELDS;
            if (isAssist && isBlank && requiredFields.contains(fieldName)) throw new AIAssistSettingsEditorServiceException(String.format(Label.AI_Settings_Error_Required, new List<String>{fieldDescribe.getLabel()}));
            if (isBlank) continue;

            // [3] A number must sit inside its range
            if (NUMBER_RANGES.containsKey(fieldName)) {

                List<Integer> range = NUMBER_RANGES.get(fieldName);
                Decimal numberValue = (Decimal) fieldValue;
                if (numberValue < range[0] || numberValue > range[1]) throw new AIAssistSettingsEditorServiceException(buildRangeMessage(fieldName, fieldDescribe.getLabel()));
            }

            // [4] A status code list must be numbers between 100 and 599 split by commas
            if (STATUS_CODE_FIELDS.contains(fieldName)) validateStatusCodes(fieldDescribe.getLabel(), (String) fieldValue);

            // [5] The text must fit the field
            if (fieldValue instanceof String && ((String) fieldValue).length() > fieldDescribe.getLength() && fieldDescribe.getLength() > 0) throw new AIAssistSettingsEditorServiceException(String.format(Label.AI_Settings_Error_Text_Length, new List<String>{fieldDescribe.getLabel(), String.valueOf(fieldDescribe.getLength())}));

            // [6] The suggested actions display must be one of the two choices
            if (fieldName == 'SuggestedActionsDisplay__c' && String.valueOf(fieldValue) != AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_CARDS && String.valueOf(fieldValue) != AIAssistApplicationConstants.SUGGESTED_ACTIONS_DISPLAY_INLINE_BUTTONS) throw new AIAssistSettingsEditorServiceException(String.format(Label.AI_Settings_Error_Choice, new List<String>{fieldDescribe.getLabel()}));
        }

        // [7] The iteration cap must be at least the default
        if (isAssist) {

            Decimal defaultIterations = (Decimal) record.get(AIAssistSettings__c.DefaultMaxToolCallingIterations__c);
            Decimal iterationCap = (Decimal) record.get(AIAssistSettings__c.MaxToolCallingIterationsCap__c);
            if (defaultIterations != null && iterationCap != null && iterationCap < defaultIterations) throw new AIAssistSettingsEditorServiceException(Label.AI_Settings_Error_Cap_Below_Default);
        }
    }

    // Refuses a status code list that is not numbers between 100 and 599 split by commas.
    private static void validateStatusCodes(String fieldLabel, String codeList) {

        // [1] Check each code
        for (String code : codeList.split(',')) {

            Boolean isNumber = code.isNumeric() && code.length() == 3;
            Integer codeNumber = isNumber ? Integer.valueOf(code) : 0;
            if (!isNumber || codeNumber < MIN_STATUS_CODE || codeNumber > MAX_STATUS_CODE) throw new AIAssistSettingsEditorServiceException(String.format(Label.AI_Settings_Error_Status_Codes, new List<String>{fieldLabel}));
        }
    }
}
