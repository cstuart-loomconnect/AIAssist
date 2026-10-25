/*
Component Name: aiTools

=================================================================
=================================================================

Description: The AI Tools tab: the page that holds the skills, data sources and workflow actions that agents can use.

Step 1: Show the page header
Step 2: Show one tab for skills, one for data sources and one for workflow actions
Step 3: Let each tab manage its own list and wizard

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { LABELS, TAB_SKILLS, TAB_DATA_SOURCES, TAB_WORKFLOW_ACTIONS } from "./aiToolsSettings";

// The AI Tools tab. It only holds the header and the tabs; each tab does its own work.
export default class AiTools extends LightningElement {

  // Values the template reads
  labels = LABELS;
  skillsTabValue = TAB_SKILLS;
  dataSourcesTabValue = TAB_DATA_SOURCES;
  workflowActionsTabValue = TAB_WORKFLOW_ACTIONS;
}
