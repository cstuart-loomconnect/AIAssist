/*
Component Name: aiAgentWizardStepBasics

=================================================================
=================================================================

Description: Step 1 of the AI Agent Wizard: the name, API name, description, record pages, prompt template, persona and greeting.

Step 1: Show the fields of the draft, with the problems the tab found
Step 2: Make the API name from the name until the admin edits it
Step 3: Search for the objects the agent appears on
Step 4: Tell the tab what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import searchObjects from "@salesforce/apex/AIAgentWizardController.searchObjects";
import { FIELD_AGENT_NAME, FIELD_DEVELOPER_NAME, FIELD_OBJECTS, SEARCH_MIN_LENGTH, SEARCH_DELAY_MILLISECONDS, API_NAME_MAX_LENGTH, NO_TEXT, LABELS } from "./aiAgentWizardStepBasicsSettings";
import { buildDeveloperName, buildFormElementClass, buildObjectChips, buildSearchMatches, buildTemplateViews, formatProblemCount, formatErrorMessage } from "./aiAgentWizardStepBasicsHelper";

// Step 1. It shows the draft and reports every change to the tab.
export default class AiAgentWizardStepBasics extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The tab's draft: the names, objects, prompt template, persona and greeting are read here
  @api promptTemplates = []; // [AIAgentWizardDataStructure.PromptTemplateOption]
  @api objectOptions = []; // [AIAgentWizardDataStructure.ObjectOption] for the labels of the chosen objects
  @api fieldErrors = {}; // The problems to show, keyed by field name: { agentName, developerName, objectApiNames }
  @api showErrors = false; // True once Next was pressed with a problem on this step

  // Values the template reads
  labels = LABELS;
  apiNameMaxLength = API_NAME_MAX_LENGTH;

  // State of the step
  isApiNameEdited = false;
  searchText = NO_TEXT;
  searchResults = [];
  foundOptions = [];
  isSearching = false;
  hasSearched = false;
  searchErrorMessage = NO_TEXT;
  searchTimer = null;
  searchRunId = 0;

  // Lifecycle methods
  connectedCallback() {

    // [1] An API name that is not the one the name would make was typed by hand, so it is left alone
    const hasApiName = Boolean(this.draft.developerName);
    const builtName = buildDeveloperName(this.draft.agentName);
    this.isApiNameEdited = hasApiName && this.draft.developerName !== builtName;
  }

  disconnectedCallback() {

    // [1] Stop a search that is waiting
    clearTimeout(this.searchTimer);
  }

  get problemCount() {

    // [1] How many fields have a message
    const problemCount = Object.keys(this.fieldErrors).length;

    return problemCount;
  }

  get showProblemBanner() {

    // [1] The banner shows once Next was pressed with a problem
    const showProblemBanner = this.showErrors && this.problemCount > 0;

    return showProblemBanner;
  }

  get problemBannerText() {

    // [1] Hand the work to the helper
    const problemBannerText = formatProblemCount(this.problemCount);

    return problemBannerText;
  }

  get nameError() {

    return this.fieldErrors[FIELD_AGENT_NAME] || NO_TEXT;
  }

  get apiNameError() {

    return this.fieldErrors[FIELD_DEVELOPER_NAME] || NO_TEXT;
  }

  get objectsError() {

    return this.fieldErrors[FIELD_OBJECTS] || NO_TEXT;
  }

  get nameClass() {

    return buildFormElementClass(this.nameError);
  }

  get apiNameClass() {

    return buildFormElementClass(this.apiNameError);
  }

  get objectsClass() {

    return buildFormElementClass(this.objectsError);
  }

  get objectChips() {

    // [1] Hand the work to the helper
    const objectChips = buildObjectChips(this.draft.objectApiNames, this.objectOptions, this.foundOptions);

    return objectChips;
  }

  get searchMatches() {

    // [1] Hand the work to the helper
    const searchMatches = buildSearchMatches(this.searchResults, this.draft.objectApiNames);

    return searchMatches;
  }

  get showMatches() {

    // [1] The list shows once a search found something
    const showMatches = this.hasSearched && this.searchMatches.length > 0;

    return showMatches;
  }

  get showNoMatches() {

    // [1] Say so when a search is done and found nothing
    const showNoMatches = this.hasSearched && !this.isSearching && this.searchMatches.length === 0 && !this.searchErrorMessage;

    return showNoMatches;
  }

  get hasSearchError() {

    return Boolean(this.searchErrorMessage);
  }

  get templateViews() {

    // [1] Hand the work to the helper
    const templateViews = buildTemplateViews(this.promptTemplates, this.draft.promptTemplateId);

    return templateViews;
  }

  // Event handlers
  handleNameInput(event) {

    // [1] Keep the name, and make the API name from it until the admin edits the API name. A saved agent keeps its API name, because code and config refer to it.
    const agentName = event.target.value;
    const changes = { agentName };
    const isSavedAgent = Boolean(this.draft.agentId);
    if (!this.isApiNameEdited && !isSavedAgent) changes.developerName = buildDeveloperName(agentName);
    this.reportChanges(changes);
  }

  handleApiNameInput(event) {

    // [1] Keep the API name the admin typed, and stop making it from the name
    this.isApiNameEdited = true;
    this.reportChanges({ developerName: event.target.value });
  }

  handleDescriptionInput(event) {

    // [1] Keep the description
    this.reportChanges({ description: event.target.value });
  }

  handlePersonaInput(event) {

    // [1] Keep the persona
    this.reportChanges({ persona: event.target.value });
  }

  handleGreetingInput(event) {

    // [1] Keep the greeting
    this.reportChanges({ greeting: event.target.value });
  }

  handleTemplateChange(event) {

    // [1] Keep the template that was picked
    this.reportChanges({ promptTemplateId: event.currentTarget.dataset.key });
  }

  handleSearchInput(event) {

    // [1] Keep what was typed, and start the list again
    this.searchText = event.target.value;
    this.searchRunId = this.searchRunId + 1;
    this.hasSearched = false;
    this.searchErrorMessage = NO_TEXT;
    clearTimeout(this.searchTimer);

    // [2] Wait for a pause in the typing before searching
    const trimmedText = this.searchText.trim();
    if (trimmedText.length < SEARCH_MIN_LENGTH) return;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runSearch(trimmedText), SEARCH_DELAY_MILLISECONDS);
  }

  handleObjectPick(event) {

    // [1] Add the object, and pass its label up so the chip can show it
    const apiName = event.currentTarget.dataset.key;
    const picked = this.searchResults.find((result) => result.apiName === apiName);
    const objectApiNames = [...(this.draft.objectApiNames || []), apiName];
    this.foundOptions = [...this.foundOptions, picked];
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { objectApiNames }, objects: [picked] } }));

    // [2] Clear the box for the next search
    this.searchText = NO_TEXT;
    this.searchResults = [];
    this.hasSearched = false;
  }

  handleObjectRemove(event) {

    // [1] Take the object off the agent
    const apiName = event.currentTarget.dataset.key;
    const objectApiNames = (this.draft.objectApiNames || []).filter((name) => name !== apiName);
    this.reportChanges({ objectApiNames });
  }

  // Private methods
  async runSearch(trimmedText) {

    // [1] Note which search this is, so a slow answer to an old search is ignored
    this.searchRunId = this.searchRunId + 1;
    const runId = this.searchRunId;
    this.isSearching = true;

    try {

      // [2] Ask Apex for the objects whose name matches
      const found = await searchObjects({ term: trimmedText });
      if (runId !== this.searchRunId) return;
      this.searchResults = found;
      this.hasSearched = true;

    } catch (error) {

      // [3] Show the reason
      if (runId === this.searchRunId) this.searchErrorMessage = formatErrorMessage(error);

    } finally {

      if (runId === this.searchRunId) this.isSearching = false;
    }
  }

  reportChanges(changes) {

    // [1] Tell the tab
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
