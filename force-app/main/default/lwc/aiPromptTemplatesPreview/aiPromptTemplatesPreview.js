/*
Component Name: aiPromptTemplatesPreview

=================================================================
=================================================================

Description: The dark panel that shows what the model receives, with merge fields filled in.

Step 1: Show each section as a heading and its text
Step 2: Colour the merge fields that were filled in
Step 3: Show a short note instead while there are errors to fix

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS } from "./aiPromptTemplatesPreviewSettings";
import { buildSectionViews, buildErrorsText } from "./aiPromptTemplatesPreviewHelper";

// The preview panel.
export default class AiPromptTemplatesPreview extends LightningElement {

  // Values passed in by the parent component
  @api sections = []; // [PreviewSection] from getPreview
  @api estimatedTokens = 0;
  @api errorCount = 0; // How many things are wrong, 0 when the preview can show
  @api isLoading = false;

  // Values the template reads
  labels = LABELS;

  get sectionViews() {

    // [1] Hand the work to the helper
    const sectionViews = buildSectionViews(this.sections);

    return sectionViews;
  }

  get hasErrors() {

    // [1] Errors hide the preview
    const hasErrors = this.errorCount > 0;

    return hasErrors;
  }

  get hasSections() {

    // [1] There is something to show once Apex has answered
    const hasSections = this.sectionViews.length > 0;

    return hasSections;
  }

  get errorsText() {

    // [1] Hand the work to the helper
    const errorsText = buildErrorsText(this.errorCount);

    return errorsText;
  }

  get tokensText() {

    // [1] Say how many tokens go with every message
    const tokenCount = this.estimatedTokens || 0;
    const tokensText = "~" + tokenCount + LABELS.tokensSuffix;

    return tokensText;
  }

  get showTokens() {

    // [1] The count means nothing while errors hide the preview
    const showTokens = !this.hasErrors && this.hasSections;

    return showTokens;
  }
}
