/*
Component Name: aiPromptTemplatesPreview

=================================================================
=================================================================

Description: The extended methods of the preview panel: the sections turned into lines the template can show.

Step 1: Give every section and piece of text a key and a class
Step 2: Build the sentence shown while there are errors

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SEGMENT_CLASS, SEGMENT_VALUE_CLASS, LABELS } from "./aiPromptTemplatesPreviewSettings";

// Builds one view per section, with one view per piece of its text.
export function buildSectionViews(sections) {

  // [1] The parent may not have a preview yet
  const sectionList = sections || [];
  const sectionViews = [];

  // [2] Build a view for each section
  sectionList.forEach((section, sectionIndex) => {
    const segmentList = section.segments || [];
    const segmentViews = [];

    // [3] Build a view for each piece of text, coloured when it is a filled-in merge field
    segmentList.forEach((segment, segmentIndex) => {
      const segmentClass = segment.isValue ? SEGMENT_VALUE_CLASS : SEGMENT_CLASS;
      segmentViews.push({ key: sectionIndex + "-" + segmentIndex, text: segment.text, segmentClass });
    });

    sectionViews.push({ key: "section-" + sectionIndex, heading: "## " + section.heading, segmentViews });
  });

  return sectionViews;
}

// Builds the sentence that says the preview waits for the errors to be fixed.
export function buildErrorsText(errorCount) {

  // [1] Say "error is" for one and "errors are" for more
  const isOne = errorCount === 1;
  const ending = isOne ? LABELS.errorsOne : LABELS.errorsMany;
  const countText = isOne ? "" : errorCount + " ";

  return LABELS.errorsStart + countText + ending;
}
