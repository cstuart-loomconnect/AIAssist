/*
Component Name: aiToolsWorkflowActions

=================================================================
=================================================================

Description: The Workflow Actions panel of the AI Tools tab: a list of workflow actions and the wizard that creates and changes them.

Step 1: Load every workflow action and show them as a table with filters and a search
Step 2: Open the wizard for a new action, or for the action the admin clicked
Step 3: Come back to the list, reloaded, when the wizard closes

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getActions from "@salesforce/apex/AIToolsWorkflowActionController.getActions";
import { VIEW_LIST, VIEW_WIZARD, FILTER_ALL, TOAST_VARIANT_ERROR, LABELS } from "./aiToolsWorkflowActionsSettings";
import { buildFilterViews, buildRowViews, formatErrorMessage } from "./aiToolsWorkflowActionsHelper";

// The Workflow Actions panel. It shows the list, or the wizard in place of it.
export default class AiToolsWorkflowActions extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the panel
  actions = [];
  view = VIEW_LIST;
  filterKey = FILTER_ALL;
  searchText = "";
  editActionId = null;
  isBusy = true;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the actions when the panel opens
    this.loadActions();
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
    const filterViews = buildFilterViews(this.actions, this.filterKey);

    return filterViews;
  }

  get rowViews() {

    // [1] Hand the work to the helper
    const rowViews = buildRowViews(this.actions, this.filterKey, this.searchText);

    return rowViews;
  }

  get showLoading() {

    // [1] The first load has no rows to show yet, so say we are waiting
    const showLoading = this.isBusy && this.actions.length === 0;

    return showLoading;
  }

  get showRefreshSpinner() {

    // [1] A reload over rows already shown keeps the small spinner
    const showRefreshSpinner = this.isBusy && this.actions.length > 0;

    return showRefreshSpinner;
  }

  get showNoActions() {

    // [1] Say so when the load is done and nothing is listed
    const showNoActions = !this.isBusy && this.rowViews.length === 0;

    return showNoActions;
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

  handleNewAction() {

    // [1] Open the wizard with no action, so it starts a new one
    this.editActionId = null;
    this.view = VIEW_WIZARD;
  }

  handleRowClick(event) {

    // [1] Open the wizard on the action the admin clicked
    this.editActionId = event.currentTarget.dataset.id;
    this.view = VIEW_WIZARD;
  }

  handleWizardClose(event) {

    // [1] Go back to the list
    this.view = VIEW_LIST;

    // [2] Load the list again when something was saved
    const hasSaved = event.detail && event.detail.saved === true;
    if (hasSaved) this.loadActions();
  }

  // Private methods
  async loadActions() {

    this.isBusy = true;

    try {

      // [1] Read every action
      this.actions = await getActions();

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
