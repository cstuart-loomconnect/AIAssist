/*
Class Name: AIPiiRegistryCoverageService

=================================================================
=================================================================

Description: Finds the objects agents read that the PII registry does not cover, and the objects an administrator can add.

Step 1: Read the target object and query of every active data source
Step 2: List the objects that have no registry, with the data sources that read them and the fields they send
Step 3: Search the org's objects by label or API name for the Add object dialog, leaving out the ones already registered

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryCoverageService {

    // Objects that are never worth registering: setup, history, sharing, feed and event copies of other objects, and metadata types.
    private static final List<String> EXCLUDED_NAME_SUFFIXES = new List<String>{'__mdt', '__share', '__history', '__feed', '__changeevent', '__e', '__x', '__b', 'share', 'history', 'feed', 'changeevent'};

    // The objects that active data sources read and that have no AIPIIRegistry__c, in name order. A registry that is switched off still counts as registered, because its row is there to switch back on.
    public static List<AIPiiRegistryDataStructure.UnprotectedObject> getUnprotectedObjects() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Note the objects the registry already has
        Set<String> registeredNames = getRegisteredNames();

        // [3] Group the active data sources by the object they read, leaving out the registered ones
        Map<String, AIPiiRegistryDataStructure.UnprotectedObject> unprotectedByName = new Map<String, AIPiiRegistryDataStructure.UnprotectedObject>();

        for (AIDataSource__c dataSource : [SELECT SourceName__c, DeveloperName__c, TargetObject__c, SOQLTemplate__c FROM AIDataSource__c WHERE IsActive__c = TRUE AND TargetObject__c != NULL WITH SYSTEM_MODE ORDER BY SourceName__c LIMIT :AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS]) {

            String objectName = dataSource.TargetObject__c.trim();
            if (registeredNames.contains(objectName.toLowerCase())) continue;

            AIPiiRegistryDataStructure.UnprotectedObject unprotected = unprotectedByName.get(objectName.toLowerCase());

            if (unprotected == null) {

                unprotected = new AIPiiRegistryDataStructure.UnprotectedObject();
                unprotected.objectApiName = objectName;
                unprotectedByName.put(objectName.toLowerCase(), unprotected);
            }

            // [4] Add the data source's name, and the fields its query selects
            unprotected.dataSourceNames.add(String.isBlank(dataSource.SourceName__c) ? dataSource.DeveloperName__c : dataSource.SourceName__c);

            for (String fieldName : getSelectedFields(dataSource.SOQLTemplate__c)) {

                if (!unprotected.fieldsSent.contains(fieldName)) unprotected.fieldsSent.add(fieldName);
            }
        }

        // [5] Put them in name order
        List<String> sortedNames = new List<String>(unprotectedByName.keySet());
        sortedNames.sort();
        List<AIPiiRegistryDataStructure.UnprotectedObject> unprotectedObjects = new List<AIPiiRegistryDataStructure.UnprotectedObject>();

        for (String sortedName : sortedNames) unprotectedObjects.add(unprotectedByName.get(sortedName));

        return unprotectedObjects;
    }

    // The objects whose label or API name contains the text, for the Add object dialog. Objects already in the registry are left out. Blank until the text is long enough to narrow the search.
    public static List<AIPiiRegistryDataStructure.ObjectOption> getObjectOptions(String searchText) {

        // [1] Refuse a user who may not use the tab, and wait for enough text to search with
        AIAssistSettingsEditorService.requireManager();
        List<AIPiiRegistryDataStructure.ObjectOption> options = new List<AIPiiRegistryDataStructure.ObjectOption>();
        String lowerSearch = String.isBlank(searchText) ? '' : searchText.trim().toLowerCase();
        if (lowerSearch.length() < AIAssistApplicationConstants.PII_OBJECT_SEARCH_MIN_LENGTH) return options;

        // [2] Find the objects that match, in label order, that can be queried and are not registered
        Set<String> registeredNames = getRegisteredNames();
        Map<String, Schema.SObjectType> typesByName = Schema.getGlobalDescribe();
        Map<String, Schema.DescribeSObjectResult> describeByLabel = new Map<String, Schema.DescribeSObjectResult>();

        for (String typeName : typesByName.keySet()) {

            if (registeredNames.contains(typeName) || isExcludedName(typeName)) continue;

            Boolean isNameMatch = typeName.contains(lowerSearch);
            Boolean isLabelMatch = typesByName.get(typeName).getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getLabel().toLowerCase().contains(lowerSearch);
            if (!isNameMatch && !isLabelMatch) continue;

            Schema.DescribeSObjectResult describeResult = typesByName.get(typeName).getDescribe();
            if (!describeResult.isQueryable() || !describeResult.isAccessible() || describeResult.isCustomSetting()) continue;

            describeByLabel.put(describeResult.getLabel().toLowerCase() + '|' + typeName, describeResult);
        }

        List<String> sortedKeys = new List<String>(describeByLabel.keySet());
        sortedKeys.sort();

        // [3] Build an option for the first few, with how many fields each has
        Set<String> optionNames = new Set<String>();

        for (String sortedKey : sortedKeys) {

            if (options.size() >= AIAssistApplicationConstants.PII_OBJECT_SEARCH_MAX_RESULTS) break;

            Schema.DescribeSObjectResult describeResult = describeByLabel.get(sortedKey);
            AIPiiRegistryDataStructure.ObjectOption option = new AIPiiRegistryDataStructure.ObjectOption();
            option.objectApiName = describeResult.getName();
            option.objectLabel = describeResult.getLabel();
            option.fieldCount = describeResult.fields.getMap().size();
            option.dataSourceCount = 0;
            options.add(option);
            optionNames.add(option.objectApiName);
        }

        // [4] Count the active data sources that read each one
        if (!optionNames.isEmpty()) {

            Map<String, Integer> countByLowerName = new Map<String, Integer>();

            for (AggregateResult countRow : [SELECT TargetObject__c targetObject, COUNT(Id) dataSourceCount FROM AIDataSource__c WHERE IsActive__c = TRUE AND TargetObject__c IN :optionNames WITH SYSTEM_MODE GROUP BY TargetObject__c]) {

                countByLowerName.put(((String) countRow.get('targetObject')).toLowerCase(), (Integer) countRow.get('dataSourceCount'));
            }

            for (AIPiiRegistryDataStructure.ObjectOption option : options) {

                Integer dataSourceCount = countByLowerName.get(option.objectApiName.toLowerCase());
                option.dataSourceCount = dataSourceCount == null ? 0 : dataSourceCount;
            }
        }

        return options;
    }

    // The API names, lower case, of every object that has a registry row.
    private static Set<String> getRegisteredNames() {

        // [1] Read the object of each registry
        Set<String> registeredNames = new Set<String>();

        for (AIPIIRegistry__c registry : [SELECT ObjectAPIName__c FROM AIPIIRegistry__c WHERE ObjectAPIName__c != NULL WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.PII_REGISTRY_LIST_MAX_RESULTS]) {

            registeredNames.add(registry.ObjectAPIName__c.toLowerCase());
        }

        return registeredNames;
    }

    // True for the kinds of object nobody means to mask: history, sharing and feed rows, events, and metadata types.
    private static Boolean isExcludedName(String lowerTypeName) {

        // [1] Match the end of the API name
        for (String suffix : EXCLUDED_NAME_SUFFIXES) {

            if (lowerTypeName.endsWith(suffix)) return true;
        }

        return false;
    }

    // The fields a SOQL query selects at the top level, without subqueries or functions. Blank for an Apex data source, which has no query.
    private static List<String> getSelectedFields(String soql) {

        // [1] Nothing to read without a query
        List<String> fieldNames = new List<String>();
        if (String.isBlank(soql)) return fieldNames;

        // [2] Take the text between SELECT and the first FROM
        Matcher selectMatcher = Pattern.compile('(?is)^\\s*SELECT\\s+(.*?)\\s+FROM\\s').matcher(soql);
        if (!selectMatcher.find()) return fieldNames;

        // [3] Keep each plain field, skipping a subquery or a function
        for (String selectedItem : selectMatcher.group(1).split(',')) {

            String fieldName = selectedItem.trim();
            if (String.isNotBlank(fieldName) && !fieldName.contains('(') && !fieldName.contains(')') && !fieldName.contains(' ')) fieldNames.add(fieldName);
        }

        return fieldNames;
    }
}
