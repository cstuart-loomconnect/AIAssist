/*
Class Name: AIPiiRegistryDataStructure

=================================================================
=================================================================

Description: The shapes the AI PII Registry tab (aiPiiRegistry) sends to and receives from Apex.

Step 1: RegistryView is one object in the registry, FieldView is one of its fields, and TypeOption is a PII type an administrator can choose
Step 2: RegistryPage carries the list, the limit, the types and the unprotected objects to the tab in one call
Step 3: RegistryDetail carries one object's fields and why its last sync failed
Step 4: UnprotectedObject and ObjectOption carry the warning banner and the Add object dialog
Step 5: MaskingTestRow and MaskingTestResult carry the Test masking tab

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPiiRegistryDataStructure {

    // One object in the registry: a line of the list, and the header of its pane.
    public class RegistryView {

        @AuraEnabled public Id registryId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String syncStatus; // An AIPIIRegistry__c.SyncStatus__c value.
        @AuraEnabled public Datetime lastSynced;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Integer maxFieldsToQuery;
        @AuraEnabled public Integer fieldCount; // Fields classified so far.
        @AuraEnabled public Integer piiCount; // Of those, the ones that are PII.
    }

    // One field of an object, with what the registry decided about it.
    public class FieldView {

        @AuraEnabled public Id fieldId;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isPii;
        @AuraEnabled public String piiFieldType; // Blank when the field is not PII.
        @AuraEnabled public String complianceGroup;
        @AuraEnabled public Boolean isOverridden; // True when an administrator chose Is PII or the type by hand.
    }

    // A PII type the tab offers, with the Compliance Group and masking rule it carries.
    public class TypeOption {

        @AuraEnabled public String piiFieldType;
        @AuraEnabled public String complianceGroup; // Blank when no rule gives the type a group.
        @AuraEnabled public String maskingText; // The rule's strategy, with " · redact" when the rule also redacts. "Redacted" when the type has no rule.
    }

    // An object that active data sources read but the registry does not cover.
    public class UnprotectedObject {

        @AuraEnabled public String objectApiName;
        @AuraEnabled public List<String> dataSourceNames = new List<String>();
        @AuraEnabled public List<String> fieldsSent = new List<String>(); // Blank for an Apex data source, which sets its own fields.
    }

    // Everything the tab needs when it opens.
    public class RegistryPage {

        @AuraEnabled public List<RegistryView> registries = new List<RegistryView>();
        @AuraEnabled public Integer registryLimit; // AIAssistSettings__c.MaxPIIRegistryObjects__c.
        @AuraEnabled public List<TypeOption> typeOptions = new List<TypeOption>();
        @AuraEnabled public List<UnprotectedObject> unprotectedObjects = new List<UnprotectedObject>();
    }

    // What the pane of one object shows.
    public class RegistryDetail {

        @AuraEnabled public RegistryView registry;
        @AuraEnabled public List<FieldView> fields = new List<FieldView>();
        @AuraEnabled public Boolean isFieldLimitReached = false; // The object has more fields than Max Fields To Query.
        @AuraEnabled public Integer suggestedMaxFields; // The next limit to try, blank when the limit is already the largest allowed.
    }

    // An object the Add object dialog offers.
    public class ObjectOption {

        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public Integer fieldCount;
        @AuraEnabled public Integer dataSourceCount; // Active data sources that read the object.
    }

    // One PII field of the test record: what it holds, and what the provider would get instead.
    public class MaskingTestRow {

        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String realValue;
        @AuraEnabled public String sentValue;
        @AuraEnabled public String ruleText;
    }

    // What one masking test found.
    public class MaskingTestResult {

        @AuraEnabled public List<MaskingTestRow> rows = new List<MaskingTestRow>();
    }
}
