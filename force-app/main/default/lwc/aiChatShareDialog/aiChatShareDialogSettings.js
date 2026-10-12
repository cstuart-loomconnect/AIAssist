/*
Component Name: aiChatShareDialog

=================================================================
=================================================================

Description: Settings for aiChatShareDialog: the search rules, the key that closes the dialog, event names and label text.

Step 1: Hold the search rules
Step 2: Hold the key and event names
Step 3: Hold the label text the template shows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The search starts after this many letters, and this many milliseconds after the user stops typing. The minimum mirrors the Apex search, which refuses fewer.
export const MIN_SEARCH_LENGTH = 2;
export const SEARCH_DELAY_MS = 300;

// The key that closes the dialog, and the text that stands in for a name in a label
export const KEY_ESCAPE = "Escape";
export const NAME_PLACEHOLDER = "{0}";

// Events sent to the parent
export const EVENT_SEARCH = "search"; // detail: { text }
export const EVENT_SHARE = "share"; // detail: { userId }
export const EVENT_UNSHARE = "unshare"; // detail: { userId }
export const EVENT_CLOSE = "close"; // No detail

// Label text shown in the template. removeAccess keeps {0} for the person's name.
export const LABELS = {
  heading: "Share this conversation",
  hint: "People you share with can read this conversation. They cannot reply to it or change it, and they need access to the record it is about.",
  searchLabel: "Add a person",
  searchPlaceholder: "Search by name",
  searchMore: "Type at least 2 letters to search.",
  searching: "Searching",
  noResults: "No one found. They need an active AI Assist user setting.",
  share: "Share",
  peopleHeading: "People with access",
  noPeople: "This conversation is not shared with anyone yet.",
  removeAccess: "Remove access for {0}",
  remove: "Remove",
  loading: "Loading",
  done: "Done"
};
