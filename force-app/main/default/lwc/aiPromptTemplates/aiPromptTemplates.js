/*
Component Name: aiPromptTemplates

=================================================================
=================================================================

Description: The AI Prompt Templates tab: the list of templates on the left and the selected template on the right.

Step 1: Load the template rows and open the first one
Step 2: Load the detail of the template the admin picks, or start a blank one
Step 3: Handle activate, make default and archive, then load the rows and the detail again
Step 4: Show the archive dialog and tell the admin what happened with a toast

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getTemplateRows from "@salesforce/apex/AIPromptTemplatesController.getTemplateRows";
import getTemplateDetail from "@salesforce/apex/AIPromptTemplatesController.getTemplateDetail";
import getArchiveOptions from "@salesforce/apex/AIPromptTemplatesController.getArchiveOptions";
import archiveTemplate from "@salesforce/apex/AIPromptTemplatesController.archiveTemplate";
import activateTemplate from "@salesforce/apex/AIPromptTemplatesController.activateTemplate";
import setDefaultTemplate from "@salesforce/apex/AIPromptTemplatesController.setDefaultTemplate";
import { LABELS, TOAST_VARIANT_ERROR, TOAST_VARIANT_SUCCESS } from "./aiPromptTemplatesSettings";
import { buildNewTemplate, buildMoves, formatErrorMessage } from "./aiPromptTemplatesHelper";

// The AI Prompt Templates tab. It holds the selection, the rows and the archive dialog; the children do the rest.
export default class AiPromptTemplates extends LightningElement {

  // Values the template reads
  labels = LABELS;

  // State of the tab
  rows = [];
  savedTemplate = null;
  selectedId = null;
  isNewTemplate = false;
  isBusy = true;
  showArchiveDialog = false;
  isArchiving = false;
  archiveOptions = null;

  // Lifecycle methods
  connectedCallback() {

    // [1] Load the rows and open the first template when the tab opens
    this.loadRows(true);
  }

  get hasTemplate() {

    // [1] The detail card shows once a template or a blank one is chosen
    const hasTemplate = this.savedTemplate !== null;

    return hasTemplate;
  }

  get archiveTemplateName() {

    // [1] The name of the template being archived
    const hasTemplate = this.savedTemplate !== null;
    const archiveTemplateName = hasTemplate ? this.savedTemplate.templateName : "";

    return archiveTemplateName;
  }

  // Event handlers
  handleNewTemplate() {

    // [1] Open a blank template with nothing selected in the list
    this.selectedId = null;
    this.isNewTemplate = true;
    this.savedTemplate = buildNewTemplate();
  }

  handleSelect(event) {

    // [1] Open the template the admin clicked
    const templateId = event.detail.templateId;
    this.selectedId = templateId;
    this.isNewTemplate = false;
    this.loadDetail(templateId);
  }

  async handleSaved(event) {

    // [1] Show the saved template and say what happened
    const detail = event.detail.detail;
    const wasNew = this.isNewTemplate;
    this.savedTemplate = detail;
    this.selectedId = detail.templateId;
    this.isNewTemplate = false;
    this.showToast(wasNew ? LABELS.created : LABELS.saved, TOAST_VARIANT_SUCCESS);

    // [2] Load the rows again so the list shows the change
    await this.loadRows(false);
  }

  async handleActivate() {

    // [1] Activate the template, then load everything again
    await this.runChange(() => activateTemplate({ templateId: this.selectedId }), LABELS.activated);
  }

  async handleMakeDefault() {

    // [1] Make the template the default, then load everything again
    await this.runChange(() => setDefaultTemplate({ templateId: this.selectedId }), LABELS.madeDefault);
  }

  async handleArchiveRequest() {

    // [1] Ask Apex where the agents can go
    this.isBusy = true;

    try {

      // [2] Open the dialog with the answer
      this.archiveOptions = await getArchiveOptions({ templateId: this.selectedId });
      this.showArchiveDialog = true;

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  handleArchiveCancel() {

    // [1] Close the dialog and change nothing
    this.showArchiveDialog = false;
  }

  async handleArchiveConfirm(event) {

    // [1] Build the moves and archive
    const moves = buildMoves(event.detail.moves);
    this.isArchiving = true;

    try {

      // [2] Archive, close the dialog and load everything again
      await archiveTemplate({ templateId: this.selectedId, moves });
      this.showArchiveDialog = false;
      this.showToast(LABELS.archived, TOAST_VARIANT_SUCCESS);
      await this.refreshAll();

    } catch (error) {

      // [3] Keep the dialog open and show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

    } finally {

      this.isArchiving = false;
    }
  }

  // Private methods
  async runChange(change, successMessage) {

    this.isBusy = true;

    try {

      // [1] Run the change in Apex
      await change();
      this.showToast(successMessage, TOAST_VARIANT_SUCCESS);

      // [2] Load the rows and the detail again
      await this.refreshAll();

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  async refreshAll() {

    // [1] Reload the list, then the selected template
    await this.loadRows(false);
    if (this.selectedId) await this.loadDetail(this.selectedId);
  }

  async loadRows(shouldOpenFirst) {

    this.isBusy = true;

    try {

      // [1] Read every template row
      this.rows = await getTemplateRows();

      // [2] Open the first template when nothing is open yet
      const hasRows = this.rows.length > 0;
      if (shouldOpenFirst && hasRows) {
        this.selectedId = this.rows[0].templateId;
        await this.loadDetail(this.selectedId);
      }

    } catch (error) {

      // [3] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

    } finally {

      this.isBusy = false;
    }
  }

  async loadDetail(templateId) {

    this.isBusy = true;

    try {

      // [1] Read the whole template, unless the admin has picked another one meanwhile
      const detail = await getTemplateDetail({ templateId });
      const isStillSelected = this.selectedId === templateId && !this.isNewTemplate;
      if (isStillSelected) this.savedTemplate = detail;

    } catch (error) {

      // [2] Show the reason
      this.showToast(formatErrorMessage(error), TOAST_VARIANT_ERROR);

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
