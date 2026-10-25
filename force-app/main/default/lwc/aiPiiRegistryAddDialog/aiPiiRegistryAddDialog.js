/*
Component Name: aiPiiRegistryAddDialog

=================================================================
=================================================================

Description: The dialog that finds an object and adds it to the registry.

Step 1: Search the org's objects as the admin types, leaving out the ones already registered
Step 2: Show the chosen object's field count and the field limit to read
Step 3: Tell the tab whether the admin cancelled or added the object

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import getObjectOptions from "@salesforce/apex/AIPiiRegistryController.getObjectOptions";
import { LABELS, SEARCH_MIN_LENGTH, SEARCH_DELAY_MS, DEFAULT_MAX_FIELDS, HINT_CLASS, HINT_WARNING_CLASS, EVENT_CANCEL, EVENT_ADD, NO_TEXT } from "./aiPiiRegistryAddDialogSettings";
import { buildOptionViews, buildFieldHint, isValidMaxFields, formatErrorMessage } from "./aiPiiRegistryAddDialogHelper";

// The Add object dialog.
export default class AiPiiRegistryAddDialog extends LightningElement {

  // Values passed in by the parent component
  @api searchText = NO_TEXT; // What to search for when the dialog opens, such as the object a banner row named
  @api isSaving = false; // True while the object is added, so the buttons wait
  @api errorMessage = NO_TEXT; // The message from the last refused add, or blank

  // Values the template reads
  labels = LABELS;

  // State of the dialog
  query = NO_TEXT;
  options = [];
  selectedName = NO_TEXT;
  maxFields = DEFAULT_MAX_FIELDS;
  isSearching = false;
  searchErrorMessage = NO_TEXT;
  hasSearched = false;
  searchTimer = null;

  connectedCallback() {

    // [1] Start from the text the tab passed in, and search for it straight away
    this.query = this.searchText || NO_TEXT;
    if (this.query.length >= SEARCH_MIN_LENGTH) this.runSearch();
  }

  disconnectedCallback() {

    // [1] Stop a search that has not started
    clearTimeout(this.searchTimer);
  }

  get optionViews() {

    // [1] Hand the work to the helper
    const optionViews = buildOptionViews(this.options, this.selectedName);

    return optionViews;
  }

  get hasOptions() {

    // [1] The list has at least one object
    const hasOptions = this.options.length > 0;

    return hasOptions;
  }

  get showNoMatches() {

    // [1] Say so when a search finished and found nothing
    const showNoMatches = this.hasSearched && !this.isSearching && !this.hasOptions;

    return showNoMatches;
  }

  get showSearchHint() {

    // [1] Ask for more letters until the search has enough
    const showSearchHint = !this.hasSearched && !this.isSearching;

    return showSearchHint;
  }

  get selectedOption() {

    // [1] Find the object the admin picked
    const selectedOption = this.options.find((option) => option.objectApiName === this.selectedName);

    return selectedOption;
  }

  get fieldHint() {

    // [1] Hand the work to the helper
    const fieldHint = buildFieldHint(this.selectedOption, this.maxFields);

    return fieldHint;
  }

  get fieldHintText() {

    // [1] The words of the hint
    const fieldHintText = this.fieldHint.text;

    return fieldHintText;
  }

  get fieldHintClass() {

    // [1] A warning is orange, and the count is muted
    const fieldHintClass = this.fieldHint.isWarning ? HINT_WARNING_CLASS : HINT_CLASS;

    return fieldHintClass;
  }

  get hasSearchError() {

    // [1] Show the message box only when there is a message
    const hasSearchError = Boolean(this.searchErrorMessage);

    return hasSearchError;
  }

  get hasErrorMessage() {

    // [1] Show the message box only when there is a message
    const hasErrorMessage = Boolean(this.errorMessage);

    return hasErrorMessage;
  }

  get addLabel() {

    // [1] The button says what it is doing while it saves
    const addLabel = this.isSaving ? LABELS.saving : LABELS.addAndSync;

    return addLabel;
  }

  get isAddDisabled() {

    // [1] An object must be picked, the limit must be valid, and nothing happens twice
    const isAddDisabled = !this.selectedOption || !isValidMaxFields(this.maxFields) || this.isSaving;

    return isAddDisabled;
  }

  // Event handlers
  handleQueryChange(event) {

    // [1] Keep what the admin typed, and search once they pause
    this.query = event.target.value;
    this.selectedName = NO_TEXT;
    clearTimeout(this.searchTimer);

    if (this.query.trim().length < SEARCH_MIN_LENGTH) {

      this.options = [];
      this.hasSearched = false;
      return;
    }

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runSearch(), SEARCH_DELAY_MS);
  }

  handleOptionPick(event) {

    // [1] Keep the object the admin picked
    this.selectedName = event.currentTarget.dataset.name;
  }

  handleMaxFieldsChange(event) {

    // [1] Keep the limit the admin typed
    this.maxFields = event.target.value === NO_TEXT ? null : Number(event.target.value);
  }

  handleCancel() {

    // [1] Tell the tab the admin changed their mind
    this.dispatchEvent(new CustomEvent(EVENT_CANCEL));
  }

  handleAdd() {

    // [1] Tell the tab to add the object with the limit
    this.dispatchEvent(new CustomEvent(EVENT_ADD, { detail: { objectApiName: this.selectedName, maxFieldsToQuery: this.maxFields } }));
  }

  // Private methods
  async runSearch() {

    // [1] Search for the text typed now, and remember it to ignore a late answer for older text
    const searchedQuery = this.query.trim();
    this.isSearching = true;
    this.searchErrorMessage = NO_TEXT;

    try {

      const options = await getObjectOptions({ searchText: searchedQuery });
      if (searchedQuery !== this.query.trim()) return;

      // [2] Show what was found, and pick the object when its API name was typed in full
      this.options = options;
      this.hasSearched = true;
      const exactMatch = options.find((option) => option.objectApiName.toLowerCase() === searchedQuery.toLowerCase());
      this.selectedName = exactMatch ? exactMatch.objectApiName : NO_TEXT;

    } catch (error) {

      // [3] Show the reason
      this.searchErrorMessage = formatErrorMessage(error);

    } finally {

      this.isSearching = false;
    }
  }
}
