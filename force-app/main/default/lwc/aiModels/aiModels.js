/*
Component Name: aiModels

=================================================================
=================================================================

Description: The AI Agent Models tab: list, test, create, change and switch off the connections to AI providers.

Step 1: Load every model with its provider, the providers and the named credentials
Step 2: Show the chosen model in the form, and test its connection
Step 3: Save the model, creating it when it is new
Step 4: Switch a model off after asking where its agents move to

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getModelsPage from "@salesforce/apex/AIModelsController.getModelsPage";
import testConnection from "@salesforce/apex/AIModelsController.testConnection";
import saveModel from "@salesforce/apex/AIModelsController.saveModel";
import getSwitchOffOptions from "@salesforce/apex/AIModelsController.getSwitchOffOptions";
import switchOffModel from "@salesforce/apex/AIModelsController.switchOffModel";
import { NEW_MODEL_KEY, FORM_KEY_SEPARATOR, NO_TEXT, TOAST_VARIANT_SUCCESS, TOAST_VARIANT_WARNING, TOAST_VARIANT_ERROR, LABELS } from "./aiModelsSettings";
import { buildModelItems, replaceModel, buildNewModel, formatErrorMessage } from "./aiModelsHelper";

// The AI Agent Models tab. It lists the models, shows the chosen one in the form and runs every Apex call.
export default class AiModels extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the tab
  models = [];
  providers = [];
  credentials = [];
  selectedKey = null;
  isBusy = true;
  isSaving = false;
  isTesting = false;
  testResult = null;
  errorMessage = NO_TEXT;
  formVersion = 0;

  // State of the switch off dialog
  isSwitchOffOpen = false;
  isSwitchOffSaving = false;
  switchOffOptions = null;
  switchOffErrorMessage = NO_TEXT;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the models when the tab opens
    this.loadModels();
  }

  // The models turned into list items.
  get modelItems() {

    // [1] Hand the work to the helper
    const modelItems = buildModelItems(this.models, this.selectedKey, this.isNewModel);

    return modelItems;
  }

  get hasModelItems() {

    // [1] The list has at least one item
    const hasModelItems = this.modelItems.length > 0;

    return hasModelItems;
  }

  get showNoModels() {

    // [1] Say so when the load is done and nothing is listed
    const showNoModels = !this.isBusy && !this.hasModelItems;

    return showNoModels;
  }

  get isNewModel() {

    // [1] The new model has its own key
    const isNewModel = this.selectedKey === NEW_MODEL_KEY;

    return isNewModel;
  }

  get selectedModel() {

    // [1] Find the saved model the admin picked
    const selectedModel = this.models.find((model) => model.modelId === this.selectedKey);

    return selectedModel;
  }

  get hasSelection() {

    // [1] Something is picked when it is the new model or a saved one
    const hasSelectedModel = Boolean(this.selectedModel);

    return this.isNewModel || hasSelectedModel;
  }

  get showChooseOne() {

    // [1] Ask the admin to pick a model when the load is done and none is picked
    const showChooseOne = !this.isBusy && !this.hasSelection;

    return showChooseOne;
  }

  get formModel() {

    // [1] The new model starts from the defaults
    if (this.isNewModel) return buildNewModel(this.providers);

    // [2] A saved model fills the form with its values
    const model = this.selectedModel;
    const formModel = model ? { ...model } : {};

    return formModel;
  }

  // One item, so the form is built again whenever the model or the saved values change.
  get formKeyItems() {

    // [1] The key changes with the chosen model and the saved version
    const key = this.selectedKey + FORM_KEY_SEPARATOR + this.formVersion;

    return [{ key }];
  }

  get switchOffModelName() {

    // [1] The dialog names the model that is selected
    const model = this.selectedModel;
    const switchOffModelName = model ? model.modelName : NO_TEXT;

    return switchOffModelName;
  }

  // Event handlers
  handleModelSelect(event) {

    // [1] Show the model the admin picked
    this.selectedKey = event.currentTarget.dataset.key;
    this.resetForm();
  }

  handleNewModel() {

    // [1] Show a form that is saved as a new model
    this.selectedKey = NEW_MODEL_KEY;
    this.resetForm();
  }

  handleCancel() {

    // [1] A new model that is cancelled is dropped, and a saved one goes back to what is saved
    if (this.isNewModel) this.selectedKey = null;
    this.resetForm();
  }

  handleConnectionEdit() {

    // [1] A result is only true for the connection that was tested, so it is cleared when the connection changes
    this.testResult = null;
  }

  async handleTest(event) {

    // [1] Test the connection as the form shows it
    this.isTesting = true;
    this.errorMessage = NO_TEXT;

    try {

      this.testResult = await testConnection({ model: event.detail.model });

    } catch (error) {

      // [2] Show the reason inside the form
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isTesting = false;
    }
  }

  async handleSave(event) {

    // [1] Save the model, creating it when it is new. Switching on tests it first, so this can take a moment.
    this.isSaving = true;
    this.errorMessage = NO_TEXT;

    try {

      const model = { ...event.detail.model, modelId: this.isNewModel ? null : this.selectedKey };
      const saveResult = await saveModel({ model });
      this.testResult = saveResult.testResult || this.testResult;

      // [2] A live model that failed its test keeps what is saved, so the form stays as it is
      if (!saveResult.isSaved) {

        this.showToast(LABELS.notSaved, TOAST_VARIANT_ERROR);
        return;
      }

      // [3] Show the saved model, which may now be the chosen one
      this.models = replaceModel(this.models, saveResult.model);
      this.selectedKey = saveResult.model.modelId;
      this.formVersion = this.formVersion + 1;

      // [4] Say what happened
      if (saveResult.isActivationRefused) this.showToast(LABELS.savedStillOff, TOAST_VARIANT_WARNING);
      else this.showToast(LABELS.saved, TOAST_VARIANT_SUCCESS);

    } catch (error) {

      // [5] Show the reason inside the form
      this.errorMessage = formatErrorMessage(error);

    } finally {

      this.isSaving = false;
    }
  }

  async handleSwitchOffRequest() {

    this.isBusy = true;

    try {

      // [1] Read the agents that use the model and the models they can move to
      this.switchOffOptions = await getSwitchOffOptions({ modelId: this.selectedKey });
      this.switchOffErrorMessage = NO_TEXT;
      this.isSwitchOffOpen = true;

    } catch (error) {

      // [2] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  async handleSwitchOffConfirm(event) {

    // [1] Move the agents and switch the model off
    this.isSwitchOffSaving = true;
    this.switchOffErrorMessage = NO_TEXT;

    try {

      this.models = await switchOffModel({ modelId: this.selectedKey, moves: event.detail.moves });

      // [2] Show the model as it is now, and close the dialog
      this.isSwitchOffOpen = false;
      this.resetForm();
      this.showToast(LABELS.switchedOff, TOAST_VARIANT_SUCCESS);

    } catch (error) {

      // [3] Show the reason inside the dialog
      this.switchOffErrorMessage = formatErrorMessage(error);

    } finally {

      this.isSwitchOffSaving = false;
    }
  }

  handleSwitchOffCancel() {

    // [1] Close the dialog and leave the model as it is
    this.isSwitchOffOpen = false;
  }

  // Private methods
  async loadModels() {

    try {

      // [1] Read the models, the providers and the named credentials
      const page = await getModelsPage();
      this.models = page.models;
      this.providers = page.providers;
      this.credentials = page.credentials;

    } catch (error) {

      // [2] Show the reason
      const message = formatErrorMessage(error);
      this.showToast(message, TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  resetForm() {

    // [1] Build the form again from what is saved, and clear what the last model showed
    this.testResult = null;
    this.errorMessage = NO_TEXT;
    this.formVersion = this.formVersion + 1;
  }

  showToast(message, variant) {

    // [1] Show the message at the top of the page
    const toastEvent = new ShowToastEvent({ message, variant });
    this.dispatchEvent(toastEvent);
  }
}
