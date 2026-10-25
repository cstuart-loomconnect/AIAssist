/*
Component Name: aiAssistSettingsPanel

=================================================================
=================================================================

Description: One settings object on the Settings tab, with Org-wide, Profiles and Users sub-tabs.

Step 1: Show the organisation row, or the profiles or users that have a row, as a list beside the form
Step 2: Let the admin find a profile or user and start a new row that begins as a copy of the organisation values
Step 3: Save, or delete, one row through Apex and tell the Settings tab to reload

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import saveSettingsRow from "@salesforce/apex/AIAssistSettingsController.saveSettingsRow";
import deleteSettingsRow from "@salesforce/apex/AIAssistSettingsController.deleteSettingsRow";
import findOwners from "@salesforce/apex/AIAssistSettingsController.findOwners";
import { SCOPE_ORGANISATION, SCOPE_PROFILE, SETTINGS_NAME_ASSIST, EVENT_REFRESH, SEARCH_MIN_LENGTH, SEARCH_DELAY_MILLISECONDS, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_ERROR, CONFIRM_VARIANT, SUB_TAB_CLASS, SUB_TAB_ACTIVE_CLASS, FORM_KEY_SEPARATOR, NO_TEXT, LABELS } from "./aiAssistSettingsPanelSettings";
import { findOrganisationRow, buildEntries, filterGroupsToOverridable, buildFormValues, formatErrorMessage, buildSubTabs } from "./aiAssistSettingsPanelHelper";

// One settings object on the Settings tab. The Settings tab gives it the rows and the groups of fields; the panel handles the sub-tabs, the lists, searching and saving.
export default class AiAssistSettingsPanel extends LightningElement {

  // Values passed in by the parent component
  @api settingsName; // AIAssistSettings__c or AIAssistUISettings__c
  @api groups = []; // [{ key, label, objectName, fields }]
  @api isOrganisationOnly = false; // True to show only the organisation row, with no Profiles or Users sub-tabs

  // Rows from the parent. A new set means the Settings tab reloaded, so the form is built again from the saved values.
  _rows = [];

  @api
  get rows() {

    return this._rows;
  }

  set rows(value) {

    this._rows = value || [];
    this.formVersion += 1;
  }

  // Values the template reads
  labels = LABELS;

  // State of the panel
  activeScope = SCOPE_ORGANISATION;
  selectedOwnerIds = {};
  newOwners = [];
  searchText = NO_TEXT;
  searchResults = [];
  isSaving = false;
  isBusy = false;
  errorMessage = NO_TEXT;
  formVersion = 0;
  searchTimer;

  // The sub-tabs with how many rows each holds.
  get subTabs() {

    // [1] Build the tabs
    const tabs = buildSubTabs(this._rows, this.newOwners);
    const tabViews = [];

    // [2] Mark the open one with its class
    tabs.forEach((tab) => {

      const isActive = tab.value === this.activeScope;
      const tabClass = isActive ? SUB_TAB_ACTIVE_CLASS : SUB_TAB_CLASS;
      tabViews.push({ ...tab, tabClass });
    });

    return tabViews;
  }

  // Which settings object and which level the panel shows.
  get isAssist() {

    // [1] Compare the settings name with AI Assist Settings
    const isAssist = this.settingsName === SETTINGS_NAME_ASSIST;

    return isAssist;
  }

  get isOrganisation() {

    // [1] Compare the open level with the organisation level
    const isOrganisation = this.activeScope === SCOPE_ORGANISATION;

    return isOrganisation;
  }

  get isProfile() {

    // [1] Compare the open level with the profile level
    const isProfile = this.activeScope === SCOPE_PROFILE;

    return isProfile;
  }

  get showScopeBadges() {

    // [1] Badges show on the organisation row of AI Assist Settings when profiles and users may override
    const canOverride = !this.isOrganisationOnly;

    return this.isAssist && this.isOrganisation && canOverride;
  }

  get showSubTabs() {

    // [1] Sub-tabs show unless the panel is organisation only
    const showSubTabs = !this.isOrganisationOnly;

    return showSubTabs;
  }

  // The text under the sub-tabs, which says what a row at this level does.
  get scopeIntro() {

    // [1] An organisation-only panel has one fixed sentence
    const isAssist = this.isAssist;
    if (this.isOrganisationOnly) return LABELS.organisationIntroOnly;

    // [2] Otherwise the sentence depends on the level and the settings object
    if (this.isOrganisation) return isAssist ? LABELS.organisationIntroAssist : LABELS.organisationIntroUi;
    if (this.isProfile) return isAssist ? LABELS.profileIntroAssist : LABELS.profileIntroUi;

    return isAssist ? LABELS.userIntroAssist : LABELS.userIntroUi;
  }

  get listLabel() {

    // [1] The list heading names profiles or users
    const listLabel = this.isProfile ? LABELS.profileListLabel : LABELS.userListLabel;

    return listLabel;
  }

  get findLabel() {

    // [1] The search box asks for a profile or a user
    const findLabel = this.isProfile ? LABELS.findProfile : LABELS.findUser;

    return findLabel;
  }

  // The profiles or users listed at this level.
  get entries() {

    // [1] Hand the work to the helper
    const entries = buildEntries(this._rows, this.newOwners, this.activeScope);

    return entries;
  }

  get entryItems() {

    // [1] Build one list item per entry, marking new ones
    const items = [];

    this.entries.forEach((entry) => {

      const label = entry.isNew ? entry.name + LABELS.newRowSuffix : entry.name;
      items.push({ ownerId: entry.ownerId, label });
    });

    return items;
  }

  get selectedOwnerId() {

    // [1] The profile or user picked at the open level
    const selectedOwnerId = this.selectedOwnerIds[this.activeScope];

    return selectedOwnerId;
  }

  get selectedEntry() {

    // [1] Find the entry the admin picked
    const selectedId = this.selectedOwnerId;
    const entry = this.entries.find((candidate) => candidate.ownerId === selectedId);

    return entry;
  }

  get hasSelectedEntry() {

    // [1] An entry was found for the picked profile or user
    const hasSelectedEntry = Boolean(this.selectedEntry);

    return hasSelectedEntry;
  }

  get hasEntries() {

    // [1] The list has at least one entry
    const hasEntries = this.entries.length > 0;

    return hasEntries;
  }

  get isSelectedNew() {

    // [1] A picked entry that is not saved yet is new
    const entry = this.selectedEntry;
    const isNew = entry ? entry.isNew : false;

    return isNew;
  }

  get canDelete() {

    // [1] A saved row can be deleted
    const canDelete = this.hasSelectedEntry && !this.isSelectedNew;

    return canDelete;
  }

  get canRemove() {

    // [1] A new row that was never saved can be removed
    const canRemove = this.hasSelectedEntry && this.isSelectedNew;

    return canRemove;
  }

  get selectedName() {

    // [1] The name of the picked entry, or nothing
    const entry = this.selectedEntry;
    const selectedName = entry ? entry.name : NO_TEXT;

    return selectedName;
  }

  get hasSearchResults() {

    // [1] The search found at least one profile or user
    const hasSearchResults = this.searchResults.length > 0;

    return hasSearchResults;
  }

  get showNoResults() {

    // [1] Say so when a search ran, found nothing and is not still running
    const hasEnoughText = this.searchText.trim().length >= SEARCH_MIN_LENGTH;

    return hasEnoughText && !this.hasSearchResults && !this.isBusy;
  }

  // The groups the form shows for this level.
  get formGroups() {

    // [1] A profile or user row of AI Assist Settings holds only the overridable fields
    const needsFiltering = this.isAssist && !this.isOrganisation;
    const formGroups = needsFiltering ? filterGroupsToOverridable(this.groups) : this.groups;

    return formGroups;
  }

  get formValues() {

    // [1] The organisation row, or the chosen entry
    const organisationRow = findOrganisationRow(this._rows);
    const entry = this.isOrganisation ? { row: organisationRow } : this.selectedEntry;

    // [2] Hand the work to the helper
    const formValues = buildFormValues(entry, organisationRow, this.formGroups);

    return formValues;
  }

  // One item, so the form is built again whenever the row, the level or the saved values change.
  get formKeyItems() {

    // [1] The key changes with the level, the chosen owner and the saved version
    const key = this.activeScope + FORM_KEY_SEPARATOR + this.selectedOwnerId + FORM_KEY_SEPARATOR + this.formVersion;

    return [{ key }];
  }

  get showForm() {

    // [1] The organisation level always has a form; other levels need a picked row
    const showForm = this.isOrganisation || this.hasSelectedEntry;

    return showForm;
  }

  get showChooseOne() {

    // [1] Ask the admin to pick a row when none is picked
    const showChooseOne = !this.isOrganisation && !this.hasSelectedEntry;

    return showChooseOne;
  }

  // Event handlers
  handleScopeChange(event) {

    // [1] Show the level the admin picked, with nothing selected until they choose
    this.activeScope = event.currentTarget.dataset.value;
    this.errorMessage = NO_TEXT;
    this.searchText = NO_TEXT;
    this.searchResults = [];
  }

  handleEntrySelect(event) {

    // [1] Select the profile or user
    this.errorMessage = NO_TEXT;
    this.selectedOwnerIds = { ...this.selectedOwnerIds, [this.activeScope]: event.detail.name };
  }

  handleSearchChange(event) {

    // [1] Wait a moment after typing stops before searching
    this.searchText = event.target.value;
    clearTimeout(this.searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runSearch(), SEARCH_DELAY_MILLISECONDS);
  }

  handleAddOwner(event) {

    // [1] Find the result the admin picked
    const ownerId = event.currentTarget.dataset.ownerId;
    const result = this.searchResults.find((candidate) => candidate.ownerId === ownerId);

    // [2] Add it as a new row that is not saved yet, and select it
    const newOwner = { ownerId: result.ownerId, name: result.name, scope: this.activeScope };
    this.newOwners = [...this.newOwners, newOwner];
    this.selectedOwnerIds = { ...this.selectedOwnerIds, [this.activeScope]: ownerId };
    this.searchText = NO_TEXT;
    this.searchResults = [];
  }

  handleRemoveNewRow() {

    // [1] Forget a new row that was never saved
    const removedId = this.selectedOwnerId;
    this.newOwners = this.newOwners.filter((owner) => owner.ownerId !== removedId);
    this.selectedOwnerIds = { ...this.selectedOwnerIds, [this.activeScope]: null };
  }

  async handleSave(event) {

    // [1] Read the values the form sent
    const ownerId = this.isOrganisation ? null : this.selectedOwnerId;
    const values = event.detail.values;
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      // [2] Save the row
      await saveSettingsRow({ settingsName: this.settingsName, scope: this.activeScope, ownerId, values });

      // [3] The row is saved now, so it stops being new, and the Settings tab reloads
      this.newOwners = this.newOwners.filter((owner) => owner.ownerId !== ownerId);
      this.showToast(LABELS.saved, TOAST_VARIANT_SUCCESS);
      this.sendRefresh();

    } catch (error) {

      // [4] Show the reason inside the form
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  async handleDeleteRow() {

    // [1] Ask first, because the profile or user goes back to the organisation values
    const confirmOptions = { message: LABELS.deleteMessage, label: LABELS.deleteTitle, variant: CONFIRM_VARIANT };
    const isConfirmed = await LightningConfirm.open(confirmOptions);
    if (!isConfirmed) return;

    this.isBusy = true;

    try {

      // [2] Delete the row, then reload
      const rowId = this.selectedEntry.row.rowId;
      await deleteSettingsRow({ settingsName: this.settingsName, rowId });
      this.selectedOwnerIds = { ...this.selectedOwnerIds, [this.activeScope]: null };
      this.showToast(LABELS.deleted, TOAST_VARIANT_SUCCESS);
      this.sendRefresh();

    } catch (error) {

      // [3] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  // Private methods
  async runSearch() {

    // [1] Wait for enough text
    const text = this.searchText.trim();

    if (text.length < SEARCH_MIN_LENGTH) {

      this.searchResults = [];
      return;
    }

    this.isBusy = true;

    try {

      // [2] Search, and hide anyone who already has a row here
      const found = await findOwners({ scope: this.activeScope, searchText: text });
      const listedIds = this.entries.map((entry) => entry.ownerId);
      this.searchResults = found.filter((owner) => !listedIds.includes(owner.ownerId));

    } catch (error) {

      // [3] Show the reason
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

  sendRefresh() {

    // [1] Tell the Settings tab to load the rows again
    const refreshEvent = new CustomEvent(EVENT_REFRESH);
    this.dispatchEvent(refreshEvent);
  }
}
