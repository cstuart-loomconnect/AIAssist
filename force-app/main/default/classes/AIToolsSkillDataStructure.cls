/*
Class Name: AIToolsSkillDataStructure

=================================================================
=================================================================

Description: The shapes the Skills panel of the AI Tools tab sends to and receives from Apex.

Step 1: SkillRow is one line of the list, with how it last tested and whether it needs attention
Step 2: SkillDetail is the whole skill the wizard edits and saves, with its tools in order
Step 3: ToolOption and AgentOption are the existing records the wizard lets the administrator choose from
Step 4: TestRequest and TestResult are what the Test step sends and gets back

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsSkillDataStructure {

    // One skill in the list.
    public class SkillRow {

        @AuraEnabled public Id skillId;
        @AuraEnabled public String skillName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String outputType; // Chat Answer, Record Change or Report.
        @AuraEnabled public String boundObject; // Blank when the skill is unbound.
        @AuraEnabled public Integer dataSourceCount = 0;
        @AuraEnabled public Integer actionCount = 0;
        @AuraEnabled public Integer agentCount = 0; // Active agents that have the skill through an active link.
        @AuraEnabled public String lastTestStatus; // Passed, Failed or Not Picked, blank when never tested.
        @AuraEnabled public Datetime lastTestedOn;
        @AuraEnabled public String attention; // Why the skill needs a look, blank when it needs none.
        @AuraEnabled public Boolean isActive;
    }

    // One tool in a skill: an existing data source or an existing workflow action.
    public class SkillTool {

        @AuraEnabled public String kind; // dataSource or action.
        @AuraEnabled public Id recordId; // The data source or workflow action.
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String bindingType; // Data sources only: Bound or Unbound.
        @AuraEnabled public String targetObject;
        @AuraEnabled public String executionType; // Workflow actions only: Read Only or Write.
        @AuraEnabled public Boolean isRequired = true;
        @AuraEnabled public Boolean isActive;
    }

    // The whole skill, as the wizard edits it.
    public class SkillDetail {

        @AuraEnabled public Id skillId; // Blank for a new skill.
        @AuraEnabled public String skillName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description; // When To Use It.
        @AuraEnabled public String instructions;
        @AuraEnabled public String outputType;
        @AuraEnabled public String boundObject;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String lastTestStatus;
        @AuraEnabled public Datetime lastTestedOn;
        @AuraEnabled public Integer agentCount = 0;
        @AuraEnabled public List<String> agentNames = new List<String>();
        @AuraEnabled public List<SkillTool> tools = new List<SkillTool>(); // In the order the instructions call them.
    }

    // An existing data source or workflow action the administrator can put in a skill.
    public class ToolOption {

        @AuraEnabled public String kind; // dataSource or action.
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String bindingType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String executionType;
        @AuraEnabled public Boolean isActive;
    }

    // An existing active agent the skill can be tested with.
    public class AgentOption {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public String modelName;
    }

    // What the Test step sends: the agent whose model answers, the record the chat is open on, and the question.
    public class TestRequest {

        @AuraEnabled public Id agentId;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String question;
    }

    // One step of the test turn, in order.
    public class TestStep {

        @AuraEnabled public String stepType;
        @AuraEnabled public String detail;
        @AuraEnabled public Boolean isSuccess;
    }

    // How a test ended.
    public class TestResult {

        @AuraEnabled public String status; // Passed, Failed or Not Picked.
        @AuraEnabled public String message; // Why it failed or was not picked, blank when it passed.
        @AuraEnabled public String replyText;
        @AuraEnabled public String suggestedActionName;
        @AuraEnabled public Decimal elapsedMilliseconds;
        @AuraEnabled public Decimal totalTokens;
        @AuraEnabled public List<TestStep> steps = new List<TestStep>();
    }
}
