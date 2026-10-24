/*
Class Name: AIToolsDataStructure

=================================================================
=================================================================

Description: The shapes the AI Tools tab (aiTools) sends to and receives from Apex for data sources.

Step 1: DataSourceRow is one line of the list, and DataSourceDetail is one data source with every field the wizard edits
Step 2: ObjectOption, FieldOption and ApexClassOption fill the pickers of the Query and Apex class steps
Step 3: SoqlValidation holds the problems found in a query, with the fix for each
Step 4: TestRequest, TestColumn and TestResult carry a test run, and AgentUse and SaveResult carry a save

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsDataStructure {

    // One line of the data source list.
    public class DataSourceRow {

        @AuraEnabled public Id dataSourceId;
        @AuraEnabled public String sourceName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String sourceType; // SOQL or Apex.
        @AuraEnabled public String targetObject;
        @AuraEnabled public String bindingType; // Bound or Unbound.
        @AuraEnabled public Decimal maxRows;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String lastTestStatus; // Passed, Partial or Failed. Blank means never tested.
        @AuraEnabled public Datetime lastTestedOn;
        @AuraEnabled public Integer agentCount; // Active agents the data source is switched on for.
    }

    // One data source with every field the wizard edits. The wizard sends it back to be tested or saved.
    public class DataSourceDetail {

        @AuraEnabled public Id dataSourceId; // Blank for a data source that is not saved yet.
        @AuraEnabled public String sourceName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String outputDescription;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String bindingType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Decimal maxRows;
        @AuraEnabled public String soqlTemplate;
        @AuraEnabled public String apexClassName;
        @AuraEnabled public String inputSchema;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String lastTestStatus;
        @AuraEnabled public Datetime lastTestedOn;
        @AuraEnabled public Integer agentCount;
    }

    // An object the query can read from.
    public class ObjectOption {

        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
    }

    // A field the user can read on an object.
    public class FieldOption {

        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType; // The lower case field type, such as string, picklist, currency, date, boolean or reference.
        @AuraEnabled public String referenceTo; // The object a lookup points to, blank for any other field.
    }

    // An Apex class that implements IAIDataSourceExecutor.
    public class ApexClassOption {

        @AuraEnabled public String className;
        @AuraEnabled public String namespacePrefix;
        @AuraEnabled public Decimal apiVersion;
        @AuraEnabled public String declaredInputNames; // Comma separated, blank when the class does not describe its inputs.
        @AuraEnabled public String declaredInputSchema; // The input schema the class returned, blank when it does not describe its inputs.
    }

    // One problem found in a query. The fix replaces fixStart to fixEnd of the query text with fixText.
    public class SoqlProblem {

        @AuraEnabled public String severity; // Error or Warning.
        @AuraEnabled public Integer line;
        @AuraEnabled public String message;
        @AuraEnabled public String fixLabel; // Blank when there is no fix.
        @AuraEnabled public Integer fixStart;
        @AuraEnabled public Integer fixEnd;
        @AuraEnabled public String fixText;
    }

    // One part of a comma separated list in a query, and where it starts. Used inside the validator only.
    public class SoqlPart {

        public String text;
        public Integer start;
    }

    // What checking a query found.
    public class SoqlValidation {

        @AuraEnabled public Boolean isValid; // True when there is no Error, warnings do not count.
        @AuraEnabled public List<SoqlProblem> problems = new List<SoqlProblem>();
        @AuraEnabled public List<String> binds = new List<String>(); // The bind names in the order they first appear.
        @AuraEnabled public String objectApiName; // The object the query reads.
        @AuraEnabled public String recordObjectApiName; // The object of the open record, worked out from the field compared to :recordId.
    }

    // What the Test step sends: the record, the values for the agent inputs and the user to check as.
    public class TestRequest {

        @AuraEnabled public Id recordId;
        @AuraEnabled public Map<String, Object> inputValues = new Map<String, Object>();
        @AuraEnabled public Id runAsUserId; // Blank to run as the person testing.
    }

    // One column of the test result table.
    public class TestColumn {

        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isRemoved; // True when the user being checked cannot read the field.
    }

    // What a test run found.
    public class TestResult {

        @AuraEnabled public String status; // Passed, Partial or Failed.
        @AuraEnabled public String message; // Why it failed. Blank when it ran.
        @AuraEnabled public Integer rowCount = 0;
        @AuraEnabled public Long elapsedMilliseconds = 0;
        @AuraEnabled public Integer queriesUsed = 0;
        @AuraEnabled public Integer queryLimit = 0;
        @AuraEnabled public String runAsName; // The user checked, blank when it was the person testing.
        @AuraEnabled public String currencyCode;
        @AuraEnabled public List<TestColumn> columns = new List<TestColumn>();
        @AuraEnabled public List<Map<String, Object>> rows = new List<Map<String, Object>>();
        @AuraEnabled public List<String> removedFields = new List<String>();
        @AuraEnabled public List<String> maskedFields = new List<String>(); // Fields the PII Registry masks before the agent sees them.
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    // One agent a data source is switched on for.
    public class AgentUse {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
    }

    // What a save did. A change that fails its test is not saved.
    public class SaveResult {

        @AuraEnabled public Boolean isSaved;
        @AuraEnabled public DataSourceRow row;
        @AuraEnabled public TestResult testResult;
    }
}
