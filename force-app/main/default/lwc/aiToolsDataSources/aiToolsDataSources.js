/*
Component Name: aiToolsDataSources

=================================================================
=================================================================

Description: The Data Sources tab of AI Tools: the list of data sources, and the wizard that builds, tests and changes one.

Step 1: Load the data sources and show them in a table with a search and filters
Step 2: Open the wizard for a new data source, or for the one that was picked
Step 3: Show the list again, reloaded, when the wizard closes or saves

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getDataSourceRows from "@salesforce/apex/AIToolsController.getDataSourceRows";
import { FILTER_ALL, NO_TEXT, TOAST_VARIANT_ERROR, LABELS } from "./aiToolsDataSourcesSettings";
import { buildFilterButtons, buildRowViews, formatErrorMessage } from "./aiToolsDataSourcesHelper";

// The Data Sources tab. It shows either the list or the wizard.
export default class AiToolsDataSources extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the tab
  rows = [];
  selectedFilter = FILTER_ALL;
  searchText = NO_TEXT;
  isBusy = true;
  isWizardOpen = false;
  editDataSourceId = null;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the data sources when the tab opens
    this.loadRows();
  }

  // The filter buttons with their counts.
  get filterButtons() {

    // [1] Hand the work to the helper
    const filterButtons = buildFilterButtons(this.rows, this.selectedFilter);

    return filterButtons;
  }

  // The rows under the filter and the search.
  get rowViews() {

    // [1] Hand the work to the helper
    const rowViews = buildRowViews(this.rows, this.selectedFilter, this.searchText);

    return rowViews;
  }

  get showLoading() {

    // [1] The first load has no rows to show yet, so say we are waiting
    const showLoading = this.isBusy && this.rows.length === 0;

    return showLoading;
  }

  get showRefreshSpinner() {

    // [1] A reload over rows already shown keeps the small spinner
    const showRefreshSpinner = this.isBusy && this.rows.length > 0;

    return showRefreshSpinner;
  }

  get showNoDataSources() {

    // [1] Say so when the load is done and no row matches
    const showNoDataSources = !this.isBusy && this.rowViews.length === 0;

    return showNoDataSources;
  }

  get isListOpen() {

    // [1] The list is shown whenever the wizard is not
    const isListOpen = !this.isWizardOpen;

    return isListOpen;
  }

  // Event handlers
  handleNewDataSource() {

    // [1] Open the wizard with no data source, so it builds a new one
    this.editDataSourceId = null;
    this.isWizardOpen = true;
  }

  handleRowClick(event) {

    // [1] Open the wizard on the data source that was picked
    this.editDataSourceId = event.currentTarget.dataset.key;
    this.isWizardOpen = true;
  }

  handleSearch(event) {

    // [1] Keep what was typed
    this.searchText = event.target.value;
  }

  handleFilterClick(event) {

    // [1] Show the filter that was picked
    this.selectedFilter = event.currentTarget.dataset.key;
  }

  handleWizardClose() {

    // [1] Go back to the list
    this.isWizardOpen = false;
    this.editDataSourceId = null;
  }

  handleWizardSaved() {

    // [1] Go back to the list and read it again, because a row changed
    this.isWizardOpen = false;
    this.editDataSourceId = null;
    this.loadRows();
  }

  // Private methods
  async loadRows() {

    this.isBusy = true;

    try {

      // [1] Read every data source
      this.rows = await getDataSourceRows();

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
