/*
Component Name: aiChatShareDialog

=================================================================
=================================================================

Description: Helper for aiChatShareDialog: builds the rows the template shows for the people with access and for the search results.

Step 1: Build a row for each person with access, with the label for its remove button
Step 2: Build a row for each search result

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, NAME_PLACEHOLDER } from "./aiChatShareDialogSettings";

// Builds a row for each person the conversation is shared with.
export function buildRecipientViews(recipients) {

  // [1] The parent may not have set any people yet
  const recipientList = recipients || [];
  const recipientViews = [];

  // [2] Build one row per person, with a remove label that names them
  recipientList.forEach((recipient) => {

    const removeLabel = LABELS.removeAccess.replace(NAME_PLACEHOLDER, recipient.name);
    recipientViews.push({ key: recipient.userId, userId: recipient.userId, name: recipient.name, subtitle: recipient.subtitle, removeLabel });
  });

  return recipientViews;
}

// Builds a row for each person the search found.
export function buildResultViews(results) {

  // [1] The parent may not have set any results yet
  const resultList = results || [];
  const resultViews = [];

  // [2] Build one row per person
  resultList.forEach((result) => {

    resultViews.push({ key: result.userId, userId: result.userId, name: result.name, subtitle: result.subtitle });
  });

  return resultViews;
}
