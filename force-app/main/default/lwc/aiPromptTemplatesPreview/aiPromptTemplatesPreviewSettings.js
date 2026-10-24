/*
Component Name: aiPromptTemplatesPreview

=================================================================
=================================================================

Description: The settings of the preview panel: class names and label text.

Step 1: Name the classes of the pieces of text
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The classes of a normal piece of text and of a merge field that was filled in.
export const SEGMENT_CLASS = "aipt-segment";
export const SEGMENT_VALUE_CLASS = "aipt-segment aipt-segment_value";

// Text shown to the user.
export const LABELS = {
  title: "What the model receives",
  tokensSuffix: " tokens sent with every message",
  footnote: "Merge fields are filled from the agent and record you pick. The reply language and any workflow actions are added after this.",
  errorsStart: "Preview appears when the ",
  errorsOne: "error is fixed.",
  errorsMany: "errors are fixed.",
  loading: "Loading preview"
};
