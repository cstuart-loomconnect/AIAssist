/*
Component Name: aiToolsSkStepInstructions

=================================================================
=================================================================

Description: The settings of step 3 of the skill wizard: the @ name pattern, the longest instructions, class names and the text shown to the admin.

Step 1: Hold the @ name pattern and the longest instructions
Step 2: Hold the class names of the tool chips
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The @ name pattern. It mirrors the AI Skill trigger, which checks the names again on save.
export const MENTION_PATTERN = /@([A-Za-z][A-Za-z0-9_]*)/g;

// The kind of tool that is called; any other kind is a workflow action, which is only suggested.
export const TOOL_KIND_DATA_SOURCE = "dataSource";

// The longest instructions. It mirrors AISkill__c.Instructions__c.
export const INSTRUCTIONS_MAX_LENGTH = 8000;

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of a tool chip: named in the instructions, or not yet.
export const CHIP_CLASS = "aitsk-chip";
export const CHIP_USED_CLASS = "aitsk-chip aitsk-chip_used";

// Text shown to the user.
export const LABELS = {
  instructions: "Instructions",
  instructionsHelp: "Number the steps in the order the tools are called. Name a tool with @ and its API name, and say what to do when a tool returns nothing.",
  instructionsPlaceholder: "1. Call @Tool_Name to read ...\n2. ...",
  toolsTitle: "Tools in this skill",
  toolsHelp: "Click a tool to add its @ name at the end of the instructions. A tick means the instructions already name it.",
  usedMark: "✓ ",
  startFromTools: "Start from the tools",
  startFromToolsHelp: "Writes one numbered step for each tool, in order, for you to finish.",
  stepCall: ". Call @",
  stepSuggest: ". Suggest @",
  stepSuggestSuffix: " when the user wants it done. Never claim it has run.",
  stepCallSuffix: " and use what it returns.",
  stepNothing: ". If a tool returns nothing, say so plainly and stop.",
  unknownPrefix: "These @ names are not tools in this skill: ",
  unknownSuffix: ". Add the tools on the Tools step, or change the names."
};
