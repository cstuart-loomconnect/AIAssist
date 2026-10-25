/*
Component Name: aiPoliciesCheckUser

=================================================================
=================================================================

Description: The settings of the Check a user box: search timing, outcome names, class names and label text.

Step 1: Name the search timing, the assignee type and the outcomes the controller uses
Step 2: Hold the class of each outcome pill
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The assignee type that makes Apex search users. Mirrors AIAssistApplicationConstants.ASSIGNEE_TYPE_USER.
export const ASSIGNEE_TYPE_USER = "User";

// How many characters the admin types before a search runs, and how long to wait after the last key press, in milliseconds.
export const SEARCH_MIN_LENGTH = 2;
export const SEARCH_DELAY_MILLISECONDS = 300;

// The outcomes Apex gives each line of the explanation. Mirror AIPoliciesDataStructure.CheckSource.outcome.
export const OUTCOME_WINS = "Wins";
export const OUTCOME_APPLIES = "Applies";

// The classes of an outcome pill: green when the policy is used, grey when it is not.
export const OUTCOME_PILL_GOOD_CLASS = "aipc-pill aipc-pill_good";
export const OUTCOME_PILL_MUTED_CLASS = "aipc-pill aipc-pill_muted";

// The class of the policy name in a line that wins.
export const WINNER_NAME_CLASS = "aipc-strong";

// The name of the event the box sends to the tab.
export const EVENT_ASSIGN = "assign";

// The text of a value when it is empty, and the text of a number that has no limit.
export const NO_TEXT = "";
export const NUMBER_LOCALE = "en-GB";
export const NO_LIMIT_TEXT = "No limit";

// Text shown to the user.
export const LABELS = {
  title: "Check a user",
  searchPlaceholder: "Type a name to see which policy they get",
  searching: "Searching",
  noMatches: "No users match.",
  getsPolicy: "Gets policy",
  applies: "Applies",
  why: "Why",
  noPolicy: "No policy",
  columnSource: "Source",
  columnPolicy: "Policy",
  columnTokens: "Daily tokens",
  columnConversations: "Conversations / 24h",
  assignPrefix: "Assign ",
  assignSuffix: " to this user",
  fallbackError: "Something went wrong. Please try again."
};
