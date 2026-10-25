/*
Component Name: aiPiiRegistry

=================================================================
=================================================================

Description: The AI PII Registry tab: the objects whose fields are masked before anything reaches the AI provider.

Step 1: Load the registered objects, the PII types and the objects agents read without cover
Step 2: Show the chosen object's fields, and save an override, a switch or a sync
Step 3: Add an object, and follow its sync until it finishes
Step 4: Open the platform log when a sync failed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import PLATFORM_LOG_OBJECT from "@salesforce/schema/AIPlatformLog__c";
import getRegistryPage from "@salesforce/apex/AIPiiRegistryController.getRegistryPage";
import getRegistryDetail from "@salesforce/apex/AIPiiRegistryController.getRegistryDetail";
import getRegistryViews from "@salesforce/apex/AIPiiRegistryController.getRegistryViews";
import addRegistryObject from "@salesforce/apex/AIPiiRegistryController.addRegistryObject";
import setRegistryActive from "@salesforce/apex/AIPiiRegistryController.setRegistryActive";
import syncRegistry from "@salesforce/apex/AIPiiRegistryController.syncRegistry";
import saveFieldOverride from "@salesforce/apex/AIPiiRegistryController.saveFieldOverride";
import resetFieldOverride from "@salesforce/apex/AIPiiRegistryController.resetFieldOverride";
import { LABELS, NO_TEXT, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_WARNING, TOAST_VARIANT_ERROR, POLL_INTERVAL_MS, POLL_MAX_ATTEMPTS, LOG_LIST_ACTION, LOG_OBJECT_PAGE_TYPE } from "./aiPiiRegistrySettings";
import { buildRegistryItems, formatLimitText, replaceRegistry, replaceField, countPiiFields, hasRunningRegistry, isRunningStatus, formatErrorMessage } from "./aiPiiRegistryHelper";

// The AI PII Registry tab. It lists the objects, shows the chosen one and runs every Apex call except the object search and the masking test, which their own components make.
export default class AiPiiRegistry extends NavigationMixin(LightningElement) {

  // Values the template reads
  labels = LABELS;

  // State of the tab
  registries = [];
  registryLimit = 0;
  typeOptions = [];
  unprotectedObjects = [];
  selectedId = null;
  detail = null;
  isBusy = true;
  isDetailBusy = false;
  isSaving = false;
  errorMessage = NO_TEXT;

  // State of the Add object dialog
  isAddOpen = false;
  addSearchText = NO_TEXT;
  isAddSaving = false;
  addErrorMessage = NO_TEXT;

  // State of the follow-up of a sync
  pollTimer = null;
  pollAttempts = 0;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the registry when the tab opens
    this.loadPage();
  }

  disconnectedCallback() {

    // [1] Stop looking for the end of a sync
    this.stopPolling();
  }

  get registryItems() {

    // [1] Hand the work to the helper
    const registryItems = buildRegistryItems(this.registries, this.selectedId);

    return registryItems;
  }

  get hasRegistryItems() {

    // [1] The list has at least one item
    const hasRegistryItems = this.registries.length > 0;

    return hasRegistryItems;
  }

  get showNoObjects() {

    // [1] Say so when the load is done and nothing is listed
    const showNoObjects = !this.isBusy && !this.hasRegistryItems;

    return showNoObjects;
  }

  get limitText() {

    // [1] Hand the work to the helper
    const limitText = formatLimitText(this.registries.length, this.registryLimit);

    return limitText;
  }

  get selectedRegistry() {

    // [1] Find the object the admin picked
    const selectedRegistry = this.registries.find((registry) => registry.registryId === this.selectedId);

    return selectedRegistry;
  }

  get hasSelection() {

    // [1] Something is picked when the list still holds it
    const hasSelection = Boolean(this.selectedRegistry);

    return hasSelection;
  }

  get showChooseOne() {

    // [1] Ask the admin to pick an object when the load is done and none is picked
    const showChooseOne = !this.isBusy && this.hasRegistryItems && !this.hasSelection;

    return showChooseOne;
  }

  get hasUnprotectedObjects() {

    // [1] The banner shows only when an object lacks cover
    const hasUnprotectedObjects = this.unprotectedObjects.length > 0;

    return hasUnprotectedObjects;
  }

  // One item, so the pane is built again whenever another object is picked.
  get detailKeyItems() {

    // [1] The key changes with the chosen object
    const detailKeyItems = [{ key: this.selectedId }];

    return detailKeyItems;
  }

  get detailFields() {

    // [1] The fields of the chosen object, or none while they load
    const detailFields = this.detail ? this.detail.fields : [];

    return detailFields;
  }

  get isFieldLimitReached() {

    // [1] The reason a sync failed, once the pane has loaded
    const isFieldLimitReached = this.detail ? this.detail.isFieldLimitReached : false;

    return isFieldLimitReached;
  }

  get suggestedMaxFields() {

    // [1] The next field limit to try
    const suggestedMaxFields = this.detail ? this.detail.suggestedMaxFields : null;

    return suggestedMaxFields;
  }

  // Event handlers
  handleSelect(event) {

    // [1] Show the object the admin picked
    this.selectedId = event.currentTarget.dataset.key;
    this.errorMessage = NO_TEXT;
    this.detail = null;
    this.loadDetail(this.selectedId);
  }

  handleAddObject() {

    // [1] Open the dialog with nothing typed
    this.addSearchText = NO_TEXT;
    this.addErrorMessage = NO_TEXT;
    this.isAddOpen = true;
  }

  handleBannerAdd(event) {

    // [1] Open the dialog with the unprotected object already typed
    this.addSearchText = event.detail.objectApiName;
    this.addErrorMessage = NO_TEXT;
    this.isAddOpen = true;
  }

  handleAddCancel() {

    // [1] Close the dialog and add nothing
    this.isAddOpen = false;
  }

  async handleAddConfirm(event) {

    // [1] Add the object and queue its first sync
    this.isAddSaving = true;
    this.addErrorMessage = NO_TEXT;

    try {

      const addedRegistry = await addRegistryObject({ objectApiName: event.detail.objectApiName, maxFieldsToQuery: event.detail.maxFieldsToQuery });

      // [2] Close the dialog, show the object, and follow its sync
      this.isAddOpen = false;
      await this.loadPage();
      this.selectedId = addedRegistry.registryId;
      this.detail = null;
      this.showToast(LABELS.added, TOAST_VARIANT_SUCCESS);
      this.startPolling();

    } catch (error) {

      // [3] Show the reason inside the dialog
      this.addErrorMessage = formatErrorMessage(error);

    } finally {

      this.isAddSaving = false;
    }
  }

  async handleActiveChange(event) {

    // [1] Switch the object on or off
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      const savedRegistry = await setRegistryActive({ registryId: this.selectedId, isActive: event.detail.isActive });
      this.registries = replaceRegistry(this.registries, savedRegistry);

      // [2] Say what happened. A switched off object is not masked, so that is a warning
      if (savedRegistry.isActive) this.showToast(LABELS.switchedOn, TOAST_VARIANT_SUCCESS);
      else this.showToast(LABELS.switchedOff, TOAST_VARIANT_WARNING);

    } catch (error) {

      // [3] Show the reason in the pane
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  async handleSync(event) {

    // [1] Queue a sync, with a larger field limit when the pane asked for one
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      const savedRegistry = await syncRegistry({ registryId: this.selectedId, maxFieldsToQuery: event.detail.maxFieldsToQuery });
      this.registries = replaceRegistry(this.registries, savedRegistry);
      this.showToast(LABELS.syncQueued, TOAST_VARIANT_SUCCESS);

      // [2] Follow the sync until it finishes
      this.startPolling();

    } catch (error) {

      // [3] Show the reason in the pane
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  async handleFieldOverride(event) {

    // [1] Save the choice the admin made on the field
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      const savedField = await saveFieldOverride({ fieldId: event.detail.fieldId, isPii: event.detail.isPii, piiFieldType: event.detail.piiFieldType });
      this.replaceSavedField(savedField);
      this.showToast(LABELS.fieldSaved, TOAST_VARIANT_SUCCESS);

    } catch (error) {

      // [2] Show the reason in the pane
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  async handleFieldReset(event) {

    // [1] Hand the field back to the automatic rules
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      const savedField = await resetFieldOverride({ fieldId: event.detail.fieldId });
      this.replaceSavedField(savedField);
      this.showToast(LABELS.fieldReset, TOAST_VARIANT_SUCCESS);

    } catch (error) {

      // [2] Show the reason in the pane
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  handleViewLog() {

    // [1] Open the list of platform logs, where the sync wrote why it failed
    const pageReference = { type: LOG_OBJECT_PAGE_TYPE, attributes: { objectApiName: PLATFORM_LOG_OBJECT.objectApiName, actionName: LOG_LIST_ACTION } };
    this[NavigationMixin.Navigate](pageReference);
  }

  // Private methods
  async loadPage() {

    try {

      // [1] Read the objects, the limit, the types and the objects without cover
      const page = await getRegistryPage();
      this.registries = page.registries;
      this.registryLimit = page.registryLimit;
      this.typeOptions = page.typeOptions;
      this.unprotectedObjects = page.unprotectedObjects;

      // [2] Follow any sync that is still running
      if (hasRunningRegistry(this.registries)) this.startPolling();

    } catch (error) {

      // [3] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  async loadDetail(registryId) {

    // [1] Read the fields of the chosen object
    this.isDetailBusy = true;

    try {

      const detail = await getRegistryDetail({ registryId });

      // [2] Ignore an answer for an object the admin has since left
      if (registryId === this.selectedId) this.detail = detail;

    } catch (error) {

      // [3] Show the reason in the pane
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isDetailBusy = false;
    }
  }

  replaceSavedField(savedField) {

    // [1] Put the saved field in the pane
    const fields = replaceField(this.detail.fields, savedField);
    this.detail = { ...this.detail, fields };

    // [2] Keep the PII count in the list up to date
    const piiCount = countPiiFields(fields);
    const registry = { ...this.selectedRegistry, piiCount };
    this.registries = replaceRegistry(this.registries, registry);
  }

  startPolling() {

    // [1] Start counting again, and look in a few seconds
    this.stopPolling();
    this.pollAttempts = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(() => this.pollRegistries(), POLL_INTERVAL_MS);
  }

  stopPolling() {

    // [1] Cancel the next look
    clearTimeout(this.pollTimer);
    this.pollTimer = null;
  }

  async pollRegistries() {

    // [1] Note how the chosen object stood before looking
    this.pollAttempts = this.pollAttempts + 1;
    const wasRunning = this.selectedRegistry ? isRunningStatus(this.selectedRegistry.syncStatus) : false;

    try {

      // [2] Read the objects as they are now
      this.registries = await getRegistryViews();

    } catch {

      // [3] A failed look is tried again next time, so nothing is shown
    }

    // [4] Show the fields of the chosen object once its sync has finished
    const selectedRegistry = this.selectedRegistry;
    if (wasRunning && selectedRegistry && !isRunningStatus(selectedRegistry.syncStatus)) this.loadDetail(this.selectedId);

    // [5] Keep looking while a sync is running, up to the limit
    const shouldKeepLooking = hasRunningRegistry(this.registries) && this.pollAttempts < POLL_MAX_ATTEMPTS;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    if (shouldKeepLooking) this.pollTimer = setTimeout(() => this.pollRegistries(), POLL_INTERVAL_MS);
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
