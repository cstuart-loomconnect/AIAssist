/*
Class Name: AIPiiRegistryEditorService

=================================================================
=================================================================

Description: Reads, adds, syncs and overrides the PII registry (AIPIIRegistry__c and AIPIIFieldMetadata__c) behind the AI PII Registry tab.

Step 1: Read every registered object with how many fields it has and how many are PII, with the PII types and the objects agents read without cover
Step 2: Read one object's fields, and why its last sync failed
Step 3: Add an object, switch it on or off, and queue a sync
Step 4: Override whether a field is PII and its type, or hand the field back to the automatic rules

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryEditorService {

    public class AIPiiRegistryEditorServiceException extends Exception {}

    // The PII types the package itself knows, offered alongside the ones the Custom Metadata rules name.
    private static final List<String> BUILT_IN_TYPES = new List<String>{
        AIAssistApplicationConstants.PII_FIELD_TYPE_NAME,
        AIAssistApplicationConstants.PII_FIELD_TYPE_EMAIL,
        AIAssistApplicationConstants.PII_FIELD_TYPE_PHONE,
        AIAssistApplicationConstants.PII_FIELD_TYPE_ADDRESS,
        AIAssistApplicationConstants.PII_FIELD_TYPE_DATE_OF_BIRTH,
        AIAssistApplicationConstants.PII_FIELD_TYPE_NATIONAL_INSURANCE_NUMBER,
        AIAssistApplicationConstants.PII_FIELD_TYPE_NHS_NUMBER,
        AIAssistApplicationConstants.PII_FIELD_TYPE_SSN,
        AIAssistApplicationConstants.PII_FIELD_TYPE_GOVERNMENT_ID,
        AIAssistApplicationConstants.PII_FIELD_TYPE_BANK_ACCOUNT,
        AIAssistApplicationConstants.PII_FIELD_TYPE_CREDIT_CARD,
        AIAssistApplicationConstants.PII_FIELD_TYPE_VAT_NUMBER,
        AIAssistApplicationConstants.PII_FIELD_TYPE_MEDICAL_RECORD,
        AIAssistApplicationConstants.PII_FIELD_TYPE_VEHICLE_REGISTRATION,
        AIAssistApplicationConstants.PII_FIELD_TYPE_IP_ADDRESS,
        AIAssistApplicationConstants.PII_FIELD_TYPE_USERNAME,
        AIAssistApplicationConstants.PII_FIELD_TYPE_PASSWORD,
        AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER
    };

    // Tests set this instead of reading custom metadata, which cannot be inserted.
    @TestVisible
    private static List<AIPiiRegistryDataStructure.TypeOption> typeOptionsForTest;

    // Everything the tab needs when it opens: the registered objects, the limit, the PII types and the objects agents read without cover.
    public static AIPiiRegistryDataStructure.RegistryPage getRegistryPage() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the four lists
        AIPiiRegistryDataStructure.RegistryPage page = new AIPiiRegistryDataStructure.RegistryPage();
        page.registries = getRegistryViews();
        page.registryLimit = getRegistryLimit();
        page.typeOptions = getTypeOptions();
        page.unprotectedObjects = AIPiiRegistryCoverageService.getUnprotectedObjects();

        return page;
    }

    // The registered objects in name order, each with its field and PII counts.
    public static List<AIPiiRegistryDataStructure.RegistryView> getRegistryViews() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Count the fields and the PII fields of each registry
        Map<Id, Integer> fieldCountByRegistryId = getFieldCounts(false);
        Map<Id, Integer> piiCountByRegistryId = getFieldCounts(true);

        // [3] Build one view for each registry
        List<AIPiiRegistryDataStructure.RegistryView> views = new List<AIPiiRegistryDataStructure.RegistryView>();

        for (AIPIIRegistry__c registry : [SELECT Id, ObjectAPIName__c, SyncStatus__c, LastSynced__c, IsActive__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WITH SYSTEM_MODE ORDER BY ObjectAPIName__c LIMIT :AIAssistApplicationConstants.PII_REGISTRY_LIST_MAX_RESULTS]) {

            views.add(buildRegistryView(registry, fieldCountByRegistryId.get(registry.Id), piiCountByRegistryId.get(registry.Id)));
        }

        return views;
    }

    // One object's fields, PII ones first, and for a failed sync whether it failed because the object has more fields than the registry reads.
    public static AIPiiRegistryDataStructure.RegistryDetail getRegistryDetail(Id registryId) {

        // [1] Refuse a user who may not use the tab, and an object that is not there
        AIAssistSettingsEditorService.requireManager();
        AIPIIRegistry__c registry = findRegistry(registryId);

        // [2] Build the view with its counts
        AIPiiRegistryDataStructure.RegistryDetail detail = new AIPiiRegistryDataStructure.RegistryDetail();
        detail.registry = buildRegistryView(registry, getFieldCounts(false).get(registry.Id), getFieldCounts(true).get(registry.Id));

        // [3] Build a view for each field
        for (AIPIIFieldMetadata__c field : [SELECT Id, FieldLabel__c, FieldAPIName__c, DataType__c, IsPII__c, PIIFieldType__c, ComplianceGroup__c, IsOverridden__c FROM AIPIIFieldMetadata__c WHERE PIIRegistry__c = :registryId WITH SYSTEM_MODE ORDER BY IsPII__c DESC, FieldLabel__c LIMIT :AIAssistApplicationConstants.MAX_PII_FIELDS_TO_QUERY_LIMIT]) {

            detail.fields.add(buildFieldView(field));
        }

        // [4] Say why a failed sync failed, and what limit to try next
        if (registry.SyncStatus__c == AIAssistApplicationConstants.PII_SYNC_STATUS_FAILED) {

            Integer maxFields = detail.registry.maxFieldsToQuery;
            String objectName = registry.ObjectAPIName__c;
            Integer fieldsToRead = maxFields + 1;
            detail.isFieldLimitReached = [SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = :objectName LIMIT :fieldsToRead].size() > maxFields;
        }

        if (detail.registry.maxFieldsToQuery < AIAssistApplicationConstants.MAX_PII_FIELDS_TO_QUERY_LIMIT) detail.suggestedMaxFields = Math.min(detail.registry.maxFieldsToQuery * 2, AIAssistApplicationConstants.MAX_PII_FIELDS_TO_QUERY_LIMIT);

        return detail;
    }

    // Adds an object to the registry and queues its first sync. Every write to the registry is explicit system mode, because the registry's fields are system-managed and the tab is only reached through the Manage Settings permission checked above.
    public static AIPiiRegistryDataStructure.RegistryView addRegistryObject(String objectApiName, Integer maxFieldsToQuery) {

        // [1] Refuse a user who may not use the tab, and an object the registry cannot hold
        AIAssistSettingsEditorService.requireManager();
        String objectName = String.isBlank(objectApiName) ? '' : objectApiName.trim();
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName.toLowerCase());
        if (objectType == null || !objectType.getDescribe().isQueryable()) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Object_Invalid);

        // [2] Refuse an object that is already there, and a registry that is full
        List<AIPIIRegistry__c> existingRegistries = [SELECT Id FROM AIPIIRegistry__c WHERE ObjectAPIName__c = :objectName WITH SYSTEM_MODE LIMIT 1];
        if (!existingRegistries.isEmpty()) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Object_Exists);

        Integer registryLimit = getRegistryLimit();
        Integer registryCount = [SELECT COUNT() FROM AIPIIRegistry__c WITH SYSTEM_MODE];
        if (registryCount >= registryLimit) throw new AIPiiRegistryEditorServiceException(String.format(Label.AI_PiiRegistry_Error_Limit_Reached, new List<String>{String.valueOf(registryLimit)}));

        // [3] Refuse a field limit the object would refuse
        Integer maxFields = maxFieldsToQuery == null ? AIAssistApplicationConstants.DEFAULT_PII_FIELDS_TO_QUERY_NEW_OBJECT : maxFieldsToQuery;
        validateMaxFields(maxFields);

        // [4] Save the registry as queued, and start the sync
        AIPIIRegistry__c registry = new AIPIIRegistry__c(Name = objectType.getDescribe().getName(), ObjectAPIName__c = objectType.getDescribe().getName(), MaxFieldsToQuery__c = maxFields, IsActive__c = true, SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED);
        Database.insert(registry, AccessLevel.SYSTEM_MODE);
        System.enqueueJob(new AIPiiRegistrySyncWorker(new List<Id>{registry.Id}));

        return buildRegistryView(registry, 0, 0);
    }

    // Switches an object on or off. While it is off its fields are not masked.
    public static AIPiiRegistryDataStructure.RegistryView setRegistryActive(Id registryId, Boolean isActive) {

        // [1] Refuse a user who may not use the tab, and an object that is not there
        AIAssistSettingsEditorService.requireManager();
        AIPIIRegistry__c registry = findRegistry(registryId);

        // [2] Save the switch
        registry.IsActive__c = isActive == true;
        Database.update(registry, AccessLevel.SYSTEM_MODE);

        return buildRegistryView(registry, getFieldCounts(false).get(registry.Id), getFieldCounts(true).get(registry.Id));
    }

    // Queues a sync of an object, raising its field limit first when a new one is given.
    public static AIPiiRegistryDataStructure.RegistryView syncRegistry(Id registryId, Integer maxFieldsToQuery) {

        // [1] Refuse a user who may not use the tab, an object that is not there, and one that is already syncing
        AIAssistSettingsEditorService.requireManager();
        AIPIIRegistry__c registry = findRegistry(registryId);
        Boolean isRunning = registry.SyncStatus__c == AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED || registry.SyncStatus__c == AIAssistApplicationConstants.PII_SYNC_STATUS_IN_PROGRESS;
        if (isRunning) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Sync_Running);

        // [2] Take the new field limit when there is one
        if (maxFieldsToQuery != null) {

            validateMaxFields(maxFieldsToQuery);
            registry.MaxFieldsToQuery__c = maxFieldsToQuery;
        }

        // [3] Mark it queued and start the sync
        registry.SyncStatus__c = AIAssistApplicationConstants.PII_SYNC_STATUS_QUEUED;
        Database.update(registry, AccessLevel.SYSTEM_MODE);
        System.enqueueJob(new AIPiiRegistrySyncWorker(new List<Id>{registry.Id}));

        return buildRegistryView(registry, getFieldCounts(false).get(registry.Id), getFieldCounts(true).get(registry.Id));
    }

    // Sets by hand whether a field is PII and what type it is. The next sync keeps the choice.
    public static AIPiiRegistryDataStructure.FieldView saveFieldOverride(Id fieldId, Boolean isPii, String piiFieldType) {

        // [1] Refuse a user who may not use the tab, and a field that is not there
        AIAssistSettingsEditorService.requireManager();
        AIPIIFieldMetadata__c field = findField(fieldId);

        // [2] A PII field has a type: the one chosen, or Other when none was
        field.IsPII__c = isPii == true;

        if (field.IsPII__c) {

            String chosenType = String.isBlank(piiFieldType) ? AIAssistApplicationConstants.PII_FIELD_TYPE_OTHER : piiFieldType.trim();
            AIPiiRegistryDataStructure.TypeOption typeOption = findTypeOption(chosenType);
            if (typeOption == null && chosenType != field.PIIFieldType__c) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Type_Invalid);

            field.PIIFieldType__c = chosenType;
            if (typeOption != null && String.isNotBlank(typeOption.complianceGroup)) field.ComplianceGroup__c = typeOption.complianceGroup;

        } else {

            field.PIIFieldType__c = null;
        }

        // [3] Save it as overridden
        field.IsOverridden__c = true;
        Database.update(field, AccessLevel.SYSTEM_MODE);

        return buildFieldView(field);
    }

    // Hands a field back to the automatic rules, which classify it again from its Data Classification.
    public static AIPiiRegistryDataStructure.FieldView resetFieldOverride(Id fieldId) {

        // [1] Refuse a user who may not use the tab, and a field that is not there
        AIAssistSettingsEditorService.requireManager();
        AIPIIFieldMetadata__c field = findField(fieldId);
        String objectName = field.PIIRegistry__r.ObjectAPIName__c;
        String fieldName = field.FieldAPIName__c;

        // [2] Read the field's Data Classification again, as the sync does
        List<FieldDefinition> fieldDefinitions = [SELECT QualifiedApiName, Label, DataType, ComplianceGroup FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = :objectName AND QualifiedApiName = :fieldName LIMIT 1];
        String complianceGroup = fieldDefinitions.isEmpty() ? null : fieldDefinitions[0].ComplianceGroup;

        // [3] Classify it and save it as automatic
        field.ComplianceGroup__c = complianceGroup;
        field.IsPII__c = String.isNotBlank(complianceGroup);
        field.PIIFieldType__c = fieldDefinitions.isEmpty() ? null : AIPiiFieldTypeClassifier.classify(fieldName, fieldDefinitions[0].Label, fieldDefinitions[0].DataType, complianceGroup);
        field.IsOverridden__c = false;
        Database.update(field, AccessLevel.SYSTEM_MODE);

        return buildFieldView(field);
    }

    // The PII types an administrator can choose, each with its Compliance Group and masking rule. The rules come from AIPiiFieldType__mdt, and the package's own types fill in the rest.
    public static List<AIPiiRegistryDataStructure.TypeOption> getTypeOptions() {

        // [1] Tests supply their own options
        if (typeOptionsForTest != null) return typeOptionsForTest;

        // [2] Read the rule of each type
        Map<String, AIPiiRegistryDataStructure.TypeOption> optionByType = new Map<String, AIPiiRegistryDataStructure.TypeOption>();

        for (AIPiiFieldType__mdt fieldTypeRule : [SELECT PIIFieldType__c, ComplianceGroup__r.MasterLabel, MaskingRule__r.Strategy__c, MaskingRule__r.Redact__c FROM AIPiiFieldType__mdt WHERE IsActive__c = TRUE AND PIIFieldType__c != NULL WITH SYSTEM_MODE ORDER BY DisplayOrder__c]) {

            if (optionByType.containsKey(fieldTypeRule.PIIFieldType__c)) continue;

            AIPiiRegistryDataStructure.TypeOption option = new AIPiiRegistryDataStructure.TypeOption();
            option.piiFieldType = fieldTypeRule.PIIFieldType__c;
            option.complianceGroup = fieldTypeRule.ComplianceGroup__r == null ? null : fieldTypeRule.ComplianceGroup__r.MasterLabel;
            option.maskingText = fieldTypeRule.MaskingRule__r == null ? AIAssistApplicationConstants.PII_RULE_NOT_APPLIED : fieldTypeRule.MaskingRule__r.Strategy__c + (fieldTypeRule.MaskingRule__r.Redact__c == true ? AIAssistApplicationConstants.PII_REDACT_SUFFIX : '');
            optionByType.put(option.piiFieldType, option);
        }

        // [3] Add each type of the package that no rule named, which is masked by redaction
        for (String builtInType : BUILT_IN_TYPES) {

            if (optionByType.containsKey(builtInType)) continue;

            AIPiiRegistryDataStructure.TypeOption option = new AIPiiRegistryDataStructure.TypeOption();
            option.piiFieldType = builtInType;
            option.maskingText = AIAssistApplicationConstants.PII_RULE_NOT_APPLIED;
            optionByType.put(builtInType, option);
        }

        // [4] Put them in name order
        List<String> typeNames = new List<String>(optionByType.keySet());
        typeNames.sort();
        List<AIPiiRegistryDataStructure.TypeOption> options = new List<AIPiiRegistryDataStructure.TypeOption>();

        for (String typeName : typeNames) options.add(optionByType.get(typeName));

        return options;
    }

    // Finds a registry by Id, or refuses.
    public static AIPIIRegistry__c findRegistry(Id registryId) {

        // [1] Query it
        List<AIPIIRegistry__c> registries = [SELECT Id, ObjectAPIName__c, SyncStatus__c, LastSynced__c, IsActive__c, MaxFieldsToQuery__c FROM AIPIIRegistry__c WHERE Id = :registryId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse one that is not there
        if (registries.isEmpty()) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Not_Found);

        return registries[0];
    }

    // Finds a field by Id, with its object, or refuses.
    private static AIPIIFieldMetadata__c findField(Id fieldId) {

        // [1] Query it
        List<AIPIIFieldMetadata__c> fields = [SELECT Id, FieldLabel__c, FieldAPIName__c, DataType__c, IsPII__c, PIIFieldType__c, ComplianceGroup__c, IsOverridden__c, PIIRegistry__r.ObjectAPIName__c FROM AIPIIFieldMetadata__c WHERE Id = :fieldId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse one that is not there
        if (fields.isEmpty()) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Field_Not_Found);

        return fields[0];
    }

    // The type option with this name, or null.
    private static AIPiiRegistryDataStructure.TypeOption findTypeOption(String piiFieldType) {

        // [1] Search the options
        for (AIPiiRegistryDataStructure.TypeOption option : getTypeOptions()) {

            if (option.piiFieldType == piiFieldType) return option;
        }

        return null;
    }

    // How many objects the registry may hold: the Maximum PII Registry Objects setting, or the most one run can sync.
    private static Integer getRegistryLimit() {

        // [1] Read the setting
        Decimal configuredLimit = AIAssistSettingsService.getSettings().MaxPIIRegistryObjects__c;

        return configuredLimit == null ? AIAssistApplicationConstants.MAX_PII_REGISTRIES_PER_RUN : Integer.valueOf(configuredLimit);
    }

    // How many fields each registry has, or only how many of them are PII.
    private static Map<Id, Integer> getFieldCounts(Boolean isPiiOnly) {

        // [1] Count the fields of each registry
        Map<Id, Integer> countByRegistryId = new Map<Id, Integer>();
        List<AggregateResult> countRows = isPiiOnly ? [SELECT PIIRegistry__c registryId, COUNT(Id) fieldCount FROM AIPIIFieldMetadata__c WHERE IsPII__c = TRUE WITH SYSTEM_MODE GROUP BY PIIRegistry__c] : [SELECT PIIRegistry__c registryId, COUNT(Id) fieldCount FROM AIPIIFieldMetadata__c WITH SYSTEM_MODE GROUP BY PIIRegistry__c];

        for (AggregateResult countRow : countRows) countByRegistryId.put((Id) countRow.get('registryId'), (Integer) countRow.get('fieldCount'));

        return countByRegistryId;
    }

    // Builds the view of a registry.
    private static AIPiiRegistryDataStructure.RegistryView buildRegistryView(AIPIIRegistry__c registry, Integer fieldCount, Integer piiCount) {

        // [1] Copy the fields across
        AIPiiRegistryDataStructure.RegistryView view = new AIPiiRegistryDataStructure.RegistryView();
        view.registryId = registry.Id;
        view.objectApiName = registry.ObjectAPIName__c;
        view.syncStatus = registry.SyncStatus__c;
        view.lastSynced = registry.LastSynced__c;
        view.isActive = registry.IsActive__c == true;
        view.maxFieldsToQuery = registry.MaxFieldsToQuery__c == null ? AIAssistApplicationConstants.DEFAULT_MAX_PII_FIELDS_TO_QUERY : Integer.valueOf(registry.MaxFieldsToQuery__c);
        view.fieldCount = fieldCount == null ? 0 : fieldCount;
        view.piiCount = piiCount == null ? 0 : piiCount;

        return view;
    }

    // Builds the view of a field.
    private static AIPiiRegistryDataStructure.FieldView buildFieldView(AIPIIFieldMetadata__c field) {

        // [1] Copy the fields across
        AIPiiRegistryDataStructure.FieldView view = new AIPiiRegistryDataStructure.FieldView();
        view.fieldId = field.Id;
        view.fieldLabel = field.FieldLabel__c;
        view.fieldApiName = field.FieldAPIName__c;
        view.dataType = field.DataType__c;
        view.isPii = field.IsPII__c == true;
        view.piiFieldType = field.PIIFieldType__c;
        view.complianceGroup = field.ComplianceGroup__c;
        view.isOverridden = field.IsOverridden__c == true;

        return view;
    }

    // Refuses a field limit the object would refuse, with a message the administrator can read.
    private static void validateMaxFields(Integer maxFields) {

        // [1] A whole number from 1 to the limit the validation rule allows
        if (maxFields < 1 || maxFields > AIAssistApplicationConstants.MAX_PII_FIELDS_TO_QUERY_LIMIT) throw new AIPiiRegistryEditorServiceException(Label.AI_PiiRegistry_Error_Max_Fields_Invalid);
    }
}
