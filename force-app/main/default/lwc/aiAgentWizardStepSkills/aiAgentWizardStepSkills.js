/*
Component Name: aiAgentWizardStepSkills

=================================================================
=================================================================

Description: Step 3 of the AI Agent Wizard: give the agent existing AI Skills. A skill brings its own data sources and workflow actions, so they do not need linking to the agent on the next two steps.

Step 1: Show the skills given to the agent and the others, with a search
Step 2: Add and remove skills, and remove one a finding names
Step 3: Report every change to the tab

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { FIELD_SKILL_IDS, NO_TEXT, LABELS } from "./aiAgentWizardStepSkillsSettings";
import { buildSkillViews, buildFindingViews, formatFindingCount } from "./aiAgentWizardStepSkillsHelper";

// Step 3. It shows the skills and reports each change to the tab.
export default class AiAgentWizardStepSkills extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: skillIds is read here
  @api options = []; // [AIAgentWizardDataStructure.SkillOption] the existing skills
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of objects
  @api findings = []; // The findings of this step: [AIAgentWizardDataStructure.Finding]

  // Values the template reads
  labels = LABELS;

  // State of the step
  searchText = NO_TEXT;

  get ids() {

    // [1] The ids of the skills given to the agent
    const ids = this.draft.skillIds || [];

    return ids;
  }

  get givenViews() {

    // [1] Hand the work to the helper
    const givenViews = buildSkillViews(this.options, this.ids, this.objectOptions, this.searchText, true);

    return givenViews;
  }

  get otherViews() {

    // [1] Hand the work to the helper
    const otherViews = buildSkillViews(this.options, this.ids, this.objectOptions, this.searchText, false);

    return otherViews;
  }

  get hasNoSkills() {

    // [1] No skill exists yet
    const hasNoSkills = (this.options || []).length === 0;

    return hasNoSkills;
  }

  get hasNoGiven() {

    // [1] Nothing is given that matches
    const hasNoGiven = this.givenViews.length === 0;

    return hasNoGiven;
  }

  get givenEmptyText() {

    // [1] Say nothing is given, or that the search hides what is
    const givenEmptyText = this.ids.length === 0 ? LABELS.emptyGiven : LABELS.noMatches;

    return givenEmptyText;
  }

  get hasNoOthers() {

    // [1] No other skill matches
    const hasNoOthers = this.otherViews.length === 0;

    return hasNoOthers;
  }

  get givenHeading() {

    // [1] The heading counts what is given
    const givenHeading = LABELS.given + " (" + this.ids.length + ")";

    return givenHeading;
  }

  get findingViews() {

    // [1] Hand the work to the helper
    const findingViews = buildFindingViews(this.findings);

    return findingViews;
  }

  get hasFindings() {

    return this.findingViews.length > 0;
  }

  get findingCountText() {

    // [1] Hand the work to the helper
    const findingCountText = formatFindingCount(this.findingViews.length);

    return findingCountText;
  }

  // Event handlers
  handleSearchInput(event) {

    // [1] Keep what was typed, and the lists follow it
    this.searchText = event.target.value;
  }

  handleAdd(event) {

    // [1] Give the skill to the agent, once
    const skillId = event.currentTarget.dataset.key;
    if (!this.ids.includes(skillId)) this.reportIds([...this.ids, skillId]);
  }

  handleRemove(event) {

    // [1] Take the skill off the agent
    const skillId = event.currentTarget.dataset.key;
    this.reportIds(this.ids.filter((id) => id !== skillId));
  }

  // Private methods
  reportIds(ids) {

    // [1] Tell the tab
    const changes = { [FIELD_SKILL_IDS]: ids };
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
