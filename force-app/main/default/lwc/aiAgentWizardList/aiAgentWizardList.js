/*
Component Name: aiAgentWizardList

=================================================================
=================================================================

Description: The list of agents the AI Agent Wizard tab opens on: search, filter and open an agent to edit.

Step 1: Read the agents from Apex and show them, active first, with the worst finding of each under its name
Step 2: Narrow the list by segment and search text
Step 3: Tell the tab when the admin wants to create or edit an agent

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import getAgentList from "@salesforce/apex/AIAgentWizardController.getAgentList";
import { SEGMENT_ALL, NO_TEXT, LABELS } from "./aiAgentWizardListSettings";
import { buildRowViews, countSegments, buildSegmentViews, filterRowViews, formatErrorMessage } from "./aiAgentWizardListHelper";

// The list of agents. It tells the tab which agent to open and keeps its own rows up to date.
export default class AiAgentWizardList extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the list
  rows = []; // [AIAgentWizardDataStructure.AgentRow]
  segment = SEGMENT_ALL;
  searchTerm = NO_TEXT;
  isLoading = true;
  errorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Read the agents when the list is shown
    this.loadRows();
  }

  get introText() {

    // [1] What an agent is, in one sentence
    const introText = LABELS.intro;

    return introText;
  }

  get hasError() {

    return Boolean(this.errorMessage);
  }

  get hasRows() {

    return this.rows.length > 0;
  }

  get isEmptyState() {

    // [1] Nothing to show once the agents are read and there are none
    const isEmptyState = !this.isLoading && !this.hasError && this.rows.length === 0;

    return isEmptyState;
  }

  get rowViews() {

    // [1] Hand the work to the helper
    const rowViews = buildRowViews(this.rows);

    return rowViews;
  }

  get visibleRowViews() {

    // [1] Keep the rows of the segment that match the search
    const visibleRowViews = filterRowViews(this.rowViews, this.segment, this.searchTerm);

    return visibleRowViews;
  }

  get hasVisibleRows() {

    return this.visibleRowViews.length > 0;
  }

  get segmentViews() {

    // [1] Count the segments, then build the buttons
    const counts = countSegments(this.rows);
    const segmentViews = buildSegmentViews(counts, this.segment);

    return segmentViews;
  }

  // Event handlers
  handleCreate() {

    // [1] Tell the tab to show the start screen
    this.dispatchEvent(new CustomEvent("createagent"));
  }

  handleSearchChange(event) {

    // [1] Keep the text
    this.searchTerm = event.target.value;
  }

  handleSegmentClick(event) {

    // [1] Show the segment of the button
    this.segment = event.currentTarget.dataset.segment;
  }

  handleRowClick(event) {

    // [1] Open the agent of the row
    const agentId = event.currentTarget.dataset.id;
    this.openAgent(agentId);
  }

  // Private methods
  async loadRows() {

    this.isLoading = true;
    this.errorMessage = NO_TEXT;

    try {

      // [1] Read every agent
      this.rows = await getAgentList();

    } catch (error) {

      // [2] Show the reason above the list
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isLoading = false;
    }
  }

  openAgent(agentId) {

    // [1] Tell the tab to open the agent in the wizard
    this.dispatchEvent(new CustomEvent("editagent", { detail: { agentId } }));
  }
}
