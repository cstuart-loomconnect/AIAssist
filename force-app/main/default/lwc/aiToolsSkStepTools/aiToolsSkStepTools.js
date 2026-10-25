/*
Component Name: aiToolsSkStepTools

=================================================================
=================================================================

Description: Step 2 of the skill wizard: pick existing data sources and workflow actions and put them in the order the instructions call them.

Step 1: Show the existing tools with a search and filters, and the tools already in the skill
Step 2: Add, move and remove tools, and mark whether each is required
Step 3: Warn about bound data sources on more than one object, switched off tools and too many tools
Step 4: Report every change to the wizard

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { FILTER_ALL, MAX_TOOLS, LABELS } from "./aiToolsSkStepToolsSettings";
import { buildFilterViews, buildOptionViews, buildToolViews, addTool, moveTool, getBoundObjects } from "./aiToolsSkStepToolsHelper";

// Step 2. It shows the tools to pick from and the tools in the skill, and reports every change to the wizard.
export default class AiToolsSkStepTools extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: tools is read here
  @api toolOptions = []; // The existing data sources and workflow actions

  // Values the template reads
  labels = LABELS;

  // State of the step
  filterKey = FILTER_ALL;
  searchText = "";

  get filterViews() {

    // [1] Hand the work to the helper
    const filterViews = buildFilterViews(this.toolOptions || [], this.filterKey);

    return filterViews;
  }

  get optionViews() {

    // [1] Hand the work to the helper
    const optionViews = buildOptionViews(this.toolOptions || [], this.draft.tools, this.filterKey, this.searchText);

    return optionViews;
  }

  get showNoOptions() {

    // [1] Say so when no option matches
    const showNoOptions = this.optionViews.length === 0;

    return showNoOptions;
  }

  get toolViews() {

    // [1] Hand the work to the helper
    const toolViews = buildToolViews(this.draft.tools);

    return toolViews;
  }

  get hasTools() {

    // [1] The skill holds a tool
    const hasTools = this.toolViews.length > 0;

    return hasTools;
  }

  get countText() {

    // [1] How many of the most allowed
    const countText = this.toolViews.length + LABELS.countSuffix;

    return countText;
  }

  get mixedObjectsText() {

    // [1] Name the objects when bound data sources are on more than one
    const boundObjects = getBoundObjects(this.draft.tools);
    const mixedObjectsText = boundObjects.length > 1 ? LABELS.mixedObjects + boundObjects.slice(1).join(", ") + LABELS.mixedObjectsSuffix : "";

    return mixedObjectsText;
  }

  get hasInactiveTool() {

    // [1] Some tool in the skill is switched off
    const hasInactiveTool = (this.draft.tools || []).some((tool) => tool.isActive === false);

    return hasInactiveTool;
  }

  get isTooMany() {

    // [1] The skill holds more than the most allowed
    const isTooMany = (this.draft.tools || []).length > MAX_TOOLS;

    return isTooMany;
  }

  // Event handlers
  handleFilterClick(event) {

    // [1] Show the filter the admin picked
    this.filterKey = event.currentTarget.dataset.key;
  }

  handleSearchChange(event) {

    // [1] Keep what the admin typed
    this.searchText = event.target.value;
  }

  handleAdd(event) {

    // [1] Find the option the admin picked and add it to the end
    const recordId = event.currentTarget.dataset.id;
    const option = (this.toolOptions || []).find((candidate) => candidate.recordId === recordId);
    if (option) this.reportChanges({ tools: addTool(this.draft.tools, option) });
  }

  handleMoveUp(event) {

    // [1] Move the tool one place up
    this.reportChanges({ tools: moveTool(this.draft.tools, Number(event.currentTarget.dataset.index), -1) });
  }

  handleMoveDown(event) {

    // [1] Move the tool one place down
    this.reportChanges({ tools: moveTool(this.draft.tools, Number(event.currentTarget.dataset.index), 1) });
  }

  handleRemove(event) {

    // [1] Take the tool out of the skill
    const toolIndex = Number(event.currentTarget.dataset.index);
    this.reportChanges({ tools: this.draft.tools.filter((tool, index) => index !== toolIndex) });
  }

  handleRequiredChange(event) {

    // [1] Keep whether the tool is required
    const toolIndex = Number(event.target.dataset.index);
    const isRequired = event.target.checked;
    this.reportChanges({ tools: this.draft.tools.map((tool, index) => (index === toolIndex ? { ...tool, isRequired } : tool)) });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
