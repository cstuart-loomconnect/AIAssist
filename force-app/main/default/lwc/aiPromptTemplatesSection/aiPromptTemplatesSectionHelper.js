/*
Component Name: aiPromptTemplatesSection

=================================================================
=================================================================

Description: The extended methods of one prompt section: the text with a merge field put in at the cursor.

Step 1: Put a token into the text where the cursor is

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Returns the text with the token put in at the cursor, and where the cursor goes next.
export function buildInsertedText(text, token, selectionStart, selectionEnd) {

  // [1] With no cursor information, the token goes at the end
  const currentText = text || "";
  const hasCursor = typeof selectionStart === "number";
  const start = hasCursor ? selectionStart : currentText.length;
  const end = hasCursor ? selectionEnd : currentText.length;

  // [2] Cut the text at the cursor and put the token between the parts
  const before = currentText.substring(0, start);
  const after = currentText.substring(end);
  const newText = before + token + after;
  const newCursor = start + token.length;

  return { newText, newCursor };
}
