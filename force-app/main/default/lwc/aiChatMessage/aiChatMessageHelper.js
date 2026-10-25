/*
Component Name: aiChatMessage

=================================================================
=================================================================

Description: Helper for aiChatMessage: gets the copy button label and icon and copies text to the clipboard.

Step 1: Choose the copy button label
Step 2: Choose the copy button icon
Step 3: Copy the message text, with a fallback when the Clipboard API is blocked

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, ICON, CLIPBOARD_FALLBACK } from "./aiChatMessageSettings";

// Gets the copy button label: "Copied" right after a copy, otherwise "Copy".
export function getCopyLabel(isCopied) {

  // [1] Pick the label for the current state
  const copyLabel = isCopied ? LABELS.copied : LABELS.copy;

  return copyLabel;
}

// Gets the copy button icon: a tick right after a copy, otherwise the copy icon.
export function getCopyIcon(isCopied) {

  // [1] Pick the icon for the current state
  const copyIcon = isCopied ? ICON.COPIED : ICON.COPY;

  return copyIcon;
}

// Copies the text to the clipboard and returns true when it worked.
export async function copyToClipboard(text) {

  // [1] Try the Clipboard API first
  try {
    const hasClipboardApi = navigator.clipboard && navigator.clipboard.writeText;

    if (hasClipboardApi) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // Clipboard API blocked - fall through to the legacy path.
  }

  // [2] Fall back to a hidden text box and the copy command
  try {
    const textArea = document.createElement(CLIPBOARD_FALLBACK.ELEMENT);
    textArea.value = text;
    textArea.setAttribute(CLIPBOARD_FALLBACK.READONLY_ATTRIBUTE, "");
    textArea.style.position = CLIPBOARD_FALLBACK.POSITION;
    textArea.style.opacity = CLIPBOARD_FALLBACK.OPACITY;
    document.body.appendChild(textArea);
    textArea.select();

    const isCopied = document.execCommand(CLIPBOARD_FALLBACK.COMMAND);
    document.body.removeChild(textArea);

    return isCopied;
  } catch {
    return false;
  }
}
