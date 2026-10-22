/*
Component Name: aiModelsForm

=================================================================
=================================================================

Description: The form for one model: the provider, the connection fields, the connection test and the save buttons.

Step 1: Show the chosen model's fields, starting from the values the tab passes in
Step 2: Keep a draft of the edits, and apply a provider's starting settings when the provider changes
Step 3: Tell the tab when the admin tests, saves, cancels or switches the model off

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import {
  LABELS,
  CONNECTION_FIELDS,
  FIELD_PROVIDER,
  FIELD_IS_ACTIVE,
  NO_TEXT,
  EVENT_CONNECTION_EDIT,
  EVENT_TEST,
  EVENT_SAVE,
  EVENT_CANCEL,
  EVENT_SWITCH_OFF
} from "./aiModelsFormSettings";
import {
  buildProviderCards,
  findProviderOption,
  buildCredentialOptions,
  applyProviderPreset,
  buildModelPayload,
  buildTemperatureHelp,
  buildUsedByText,
  buildTestView
} from "./aiModelsFormHelper";

// The form for one model. The tab gives it the saved values; the form keeps a draft and sends it back on Test and Save.
export default class AiModelsForm extends LightningElement {
  // Values passed in by the parent component
  @api model = {}; // The saved values, or the starting values of a new model. Mirrors AIModelsDataStructure.ModelView
  @api providers = []; // [{ provider, apiPath, versionHeaderName, versionHeaderValue, needsEnvironmentId, maxTemperature }]
  @api credentials = []; // [{ credentialName, label }]
  @api testResult = null; // The last AIModelsDataStructure.TestResult, or null when nothing has been tested
  @api isTesting = false; // True while a test runs, so the buttons wait
  @api isSaving = false; // True while a save runs, so the buttons wait
  @api errorMessage = NO_TEXT; // The message from the last failed call, or blank

  // Values the template reads
  labels = LABELS;

  // State of the form
  draft = {};

  // Lifecycle methods
  connectedCallback() {
    // [1] Start the draft from the saved values
    this.draft = { ...this.model };
  }

  get heading() {
    // [1] A saved model shows its saved name, a new one shows a fixed name
    const heading = this.model.modelId
      ? this.model.modelName
      : LABELS.newModelName;

    return heading;
  }

  get providerCards() {
    // [1] Hand the work to the helper
    const providerCards = buildProviderCards(
      this.providers,
      this.draft[FIELD_PROVIDER]
    );

    return providerCards;
  }

  get credentialOptions() {
    // [1] Hand the work to the helper
    const credentialOptions = buildCredentialOptions(
      this.credentials,
      this.draft.namedCredential
    );

    return credentialOptions;
  }

  get showEnvironmentId() {
    // [1] Only a provider that needs an environment shows the box
    const providerOption = findProviderOption(
      this.providers,
      this.draft[FIELD_PROVIDER]
    );
    const showEnvironmentId = Boolean(
      providerOption && providerOption.needsEnvironmentId
    );

    return showEnvironmentId;
  }

  get temperatureHelp() {
    // [1] Hand the work to the helper
    const temperatureHelp = buildTemperatureHelp(
      this.providers,
      this.draft[FIELD_PROVIDER]
    );

    return temperatureHelp;
  }

  get testView() {
    // [1] Hand the work to the helper
    const testView = buildTestView(this.testResult, this.draft.modelIdentifier);

    return testView;
  }

  get showTestFailureNote() {
    // [1] After a failed test, remind the admin what saving does
    const testView = this.testView;
    const showTestFailureNote = Boolean(testView) && !testView.isSuccess;

    return showTestFailureNote;
  }

  get showTestNote() {
    // [1] The note about what a test sends is shown unless a failure shows its own note
    const showTestNote = !this.showTestFailureNote;

    return showTestNote;
  }

  get testButtonLabel() {
    // [1] After a test the button offers another
    const testButtonLabel = this.testResult
      ? LABELS.testAgain
      : LABELS.testButton;

    return testButtonLabel;
  }

  get isWorking() {
    // [1] Nothing is clicked twice while a call runs
    const isWorking = this.isTesting || this.isSaving;

    return isWorking;
  }

  get saveLabel() {
    // [1] The button says so while it saves
    const saveLabel = this.isSaving ? LABELS.saving : LABELS.save;

    return saveLabel;
  }

  get usedByText() {
    // [1] Hand the work to the helper
    const usedByText = buildUsedByText(this.model.agentCount);

    return usedByText;
  }

  get hasErrorMessage() {
    // [1] Show the message box only when there is a message
    const hasErrorMessage = Boolean(this.errorMessage);

    return hasErrorMessage;
  }

  // Event handlers
  handleFieldChange(event) {
    // [1] Read which field changed and what it holds now
    const fieldName = event.target.dataset.field;
    const value = event.target.value;

    // [2] Keep it in the draft. A number field is kept as typed and turned into a number on send.
    this.draft = { ...this.draft, [fieldName]: value };

    // [3] A change to the connection makes an old test result untrue
    if (CONNECTION_FIELDS.includes(fieldName))
      this.dispatchEvent(new CustomEvent(EVENT_CONNECTION_EDIT));
  }

  handleProviderSelect(event) {
    // [1] Switch to the provider of the card, with its starting settings
    const nextProvider = event.currentTarget.dataset.provider;
    this.draft = applyProviderPreset(this.draft, this.providers, nextProvider);

    // [2] The connection changed
    this.dispatchEvent(new CustomEvent(EVENT_CONNECTION_EDIT));
  }

  handleActiveChange(event) {
    // [1] Read the toggle
    const isActive = event.target.checked;

    // [2] A model that is on and used by active agents is switched off by the tab, which asks where the agents go. The toggle stays on until that is done.
    const isSwitchOffRequest =
      !isActive && this.model.isActive && this.model.agentCount > 0;

    if (isSwitchOffRequest) {
      event.target.checked = true;
      this.dispatchEvent(new CustomEvent(EVENT_SWITCH_OFF));
      return;
    }

    // [3] Any other change is kept in the draft until Save
    this.draft = { ...this.draft, [FIELD_IS_ACTIVE]: isActive };
  }

  handleTest() {
    // [1] Ask the tab to test the connection as the form shows it
    const payload = buildModelPayload(this.draft);
    this.dispatchEvent(
      new CustomEvent(EVENT_TEST, { detail: { model: payload } })
    );
  }

  handleSave() {
    // [1] Ask the tab to save the model as the form shows it
    const payload = buildModelPayload(this.draft);
    this.dispatchEvent(
      new CustomEvent(EVENT_SAVE, { detail: { model: payload } })
    );
  }

  handleCancel() {
    // [1] Ask the tab to go back to what is saved
    this.dispatchEvent(new CustomEvent(EVENT_CANCEL));
  }
}
