/*
Component Name: aiToolsSkStepInstructions

=================================================================
=================================================================

Description: The extended methods of step 3 of the skill wizard: find the @ names, build the tool chips and write a first draft from the tools.

Step 1: Find the @ names in the instructions and those that are not tools in the skill
Step 2: Build one chip for each tool, ticked when the instructions name it
Step 3: Write one numbered step for each tool, for the admin to finish

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { MENTION_PATTERN, TOOL_KIND_DATA_SOURCE, CHIP_CLASS, CHIP_USED_CLASS, NO_TEXT, LABELS } from "./aiToolsSkStepInstructionsSettings";

// The @ names in the instructions, lower case, without repeats.
export function getMentionedNames(instructions) {

  // [1] Collect each name once
  const mentionedNames = [];

  for (const mention of (instructions || NO_TEXT).matchAll(MENTION_PATTERN)) {

    const mentionedName = mention[1].toLowerCase();
    if (!mentionedNames.includes(mentionedName)) mentionedNames.push(mentionedName);
  }

  return mentionedNames;
}

// The @ names in the instructions that are not the API name of a tool in the skill, as the admin typed them.
export function getUnknownMentions(instructions, tools) {

  // [1] Collect the API names of the tools
  const toolNames = (tools || []).map((tool) => (tool.developerName || NO_TEXT).toLowerCase());

  // [2] Keep each @ name that is not one of them
  const unknownMentions = [];

  for (const mention of (instructions || NO_TEXT).matchAll(MENTION_PATTERN)) {

    const mentionedName = mention[1];
    if (!toolNames.includes(mentionedName.toLowerCase()) && !unknownMentions.includes(mentionedName)) unknownMentions.push(mentionedName);
  }

  return unknownMentions;
}

// Builds one chip for each tool, ticked when the instructions already name it.
export function buildChipViews(tools, instructions) {

  // [1] Note the names already used
  const mentionedNames = getMentionedNames(instructions);

  // [2] Build one chip for each tool
  const chipViews = (tools || []).map((tool) => {

    const isUsed = mentionedNames.includes((tool.developerName || NO_TEXT).toLowerCase());

    return { key: tool.recordId, developerName: tool.developerName, label: (isUsed ? LABELS.usedMark : NO_TEXT) + "@" + tool.developerName, chipClass: isUsed ? CHIP_USED_CLASS : CHIP_CLASS };
  });

  return chipViews;
}

// Writes one numbered step for each tool in order, and a last step for when a tool returns nothing.
export function buildStarterInstructions(tools) {

  // [1] One step for each tool: a data source is called, a workflow action is suggested
  const lines = (tools || []).map((tool, toolIndex) => {

    const isAction = tool.kind !== TOOL_KIND_DATA_SOURCE;
    const line = isAction ? (toolIndex + 1) + LABELS.stepSuggest + tool.developerName + LABELS.stepSuggestSuffix : (toolIndex + 1) + LABELS.stepCall + tool.developerName + LABELS.stepCallSuffix;

    return line;
  });

  // [2] A last step for when nothing comes back
  lines.push((lines.length + 1) + LABELS.stepNothing);

  return lines.join("\n");
}

// Adds an @ name at the end of the instructions, on the same line when the text ends with a space.
export function appendMention(instructions, developerName) {

  // [1] Add a space first unless the text is empty or already ends with white space
  const currentText = instructions || NO_TEXT;
  const separator = currentText.length === 0 || /\s$/.test(currentText) ? NO_TEXT : " ";
  const appendedText = currentText + separator + "@" + developerName + " ";

  return appendedText;
}
