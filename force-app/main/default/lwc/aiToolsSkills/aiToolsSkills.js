/*
Component Name: aiToolsSkills

=================================================================
=================================================================

Description: The Skills panel of the AI Tools tab: a list of AI Skills and the wizard that builds and changes them from existing data sources and workflow actions.

Step 1: Load every skill and show them as a table with filters and a search
Step 2: Open the wizard for a new skill, or for the skill the admin clicked
Step 3: Come back to the list, reloaded, when the wizard closes

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSkills from "@salesforce/apex/AIToolsSkillController.getSkills";
import { VIEW_LIST, VIEW_WIZARD, FILTER_ALL, TOAST_VARIANT_ERROR, LABELS } from "./aiToolsSkillsSettings";
import { buildFilterViews, buildRowViews, formatErrorMessage } from "./aiToolsSkillsHelper";

// The Skills panel. It shows the list, or the wizard in place of it.
export default class AiToolsSkills extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the panel
  skills = [];
  view = VIEW_LIST;
  filterKey = FILTER_ALL;
  searchText = "";
  editSkillId = null;
  isBusy = true;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the skills when the panel opens
    this.loadSkills();
  }

  get isListView() {

    // [1] The list is shown unless the wizard is open
    const isListView = this.view === VIEW_LIST;

    return isListView;
  }

  get isWizardView() {

    // [1] The wizard is shown in place of the list
    const isWizardView = this.view === VIEW_WIZARD;

    return isWizardView;
  }

  get filterViews() {

    // [1] Hand the work to the helper
    const filterViews = buildFilterViews(this.skills, this.filterKey);

    return filterViews;
  }

  get rowViews() {

    // [1] Hand the work to the helper
    const rowViews = buildRowViews(this.skills, this.filterKey, this.searchText);

    return rowViews;
  }

  get showLoading() {

    // [1] The first load has no rows to show yet, so say we are waiting
    const showLoading = this.isBusy && this.skills.length === 0;

    return showLoading;
  }

  get showRefreshSpinner() {

    // [1] A reload over rows already shown keeps the small spinner
    const showRefreshSpinner = this.isBusy && this.skills.length > 0;

    return showRefreshSpinner;
  }

  get showNoSkills() {

    // [1] Say so when the load is done and nothing is listed
    const showNoSkills = !this.isBusy && this.rowViews.length === 0;

    return showNoSkills;
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

  handleNewSkill() {

    // [1] Open the wizard with no skill, so it starts a new one
    this.editSkillId = null;
    this.view = VIEW_WIZARD;
  }

  handleRowClick(event) {

    // [1] Open the wizard on the skill the admin clicked
    this.editSkillId = event.currentTarget.dataset.id;
    this.view = VIEW_WIZARD;
  }

  handleWizardClose(event) {

    // [1] Go back to the list
    this.view = VIEW_LIST;

    // [2] Load the list again when something was saved
    const hasSaved = event.detail && event.detail.saved === true;
    if (hasSaved) this.loadSkills();
  }

  // Private methods
  async loadSkills() {

    this.isBusy = true;

    try {

      // [1] Read every skill
      this.skills = await getSkills();

    } catch (error) {

      // [2] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
