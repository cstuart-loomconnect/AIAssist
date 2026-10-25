/*
Component Name: aiChatComposer

=================================================================
=================================================================

Description: The message box at the bottom of the chat: typing, the slash-command menu, Send and Stop, and the footnote with today's token usage.

Step 1: The parent (aiAssistChat) passes in the commands, the usage meters and whether the box is disabled or working
Step 2: The user types; a command being typed opens the slash-command menu
Step 3: Enter sends the message (Shift+Enter adds a line); while the menu is open the arrow keys move and Enter or Tab picks
Step 4: The footnote shows how much of today's token allowance is used, and the parent hears about every send, stop and menu change

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { TYPING_COMMAND_PATTERN, COMMAND_PREFIX, LEADING_SLASH_PATTERN, WHITESPACE_PATTERN, RANK_PREFIX, RANK_INSIDE, COMMAND_OPTION_ID_PREFIX, ARIA_TRUE, ARIA_FALSE, OPTION_CLASS, OPTION_CLASS_ACTIVE, SCOPE_CLASS, SCOPE_CLASS_ACTIVE, LIMIT_TYPE_TOKENS, TOKEN_WARN_PERCENT, TOKEN_FULL_PERCENT, TOKEN_RING_LENGTH, TOKEN_RING_DECIMALS, TOKEN_TONE_OK, TOKEN_TONE_WARN, TOKEN_TONE_BAD } from "./aiChatComposerSettings";

// Finds the commands that match what the user typed, split for highlighting: "/ri" matches /risk-check, /brief and /drive-renewal. Matches at the start of the name come first.
export function buildCommandMatches(commands, typedText) {

  // [1] Take the first word the user typed, without its slash, in lower case
  const typedWords = (typedText || "").trim();
  const firstWord = typedWords.split(WHITESPACE_PATTERN)[0];
  const query = firstWord.replace(LEADING_SLASH_PATTERN, "").toLowerCase();

  // [2] Look at each command the parent offered
  const commandList = commands || [];
  const matches = [];

  commandList.forEach((command) => {

    // [3] Find where the query sits in the name; no query matches from the start
    const name = command.command.replace(LEADING_SLASH_PATTERN, "");
    const index = query ? name.toLowerCase().indexOf(query) : 0;

    if (index < 0) return;

    // [4] Split the name into the part before the match, the match and the part after it
    const before = `${COMMAND_PREFIX}${name.slice(0, index)}`;
    const match = name.slice(index, index + query.length);
    const after = name.slice(index + query.length);
    const rank = index === 0 ? RANK_PREFIX : RANK_INSIDE;

    matches.push({ ...command, key: command.id, before, match, after, rank });
  });

  // [5] Matches at the start of the name come first
  const sortedMatches = matches.sort((first, second) => first.rank - second.rank);

  return sortedMatches;
}

// Turns each matching command into what the menu row needs: its id, whether it is highlighted and its classes.
export function buildMatchViews(matches, activeIndex) {

  // [1] Build one view for each match
  const matchViews = matches.map((command, index) => {

    const isSelected = index === activeIndex;

    return { ...command, index, optionId: buildOptionId(index), selected: isSelected ? ARIA_TRUE : ARIA_FALSE, className: isSelected ? OPTION_CLASS_ACTIVE : OPTION_CLASS, scopeClass: isSelected ? SCOPE_CLASS_ACTIVE : SCOPE_CLASS };
  });

  return matchViews;
}

// Says whether the box holds only a command being typed, such as "/ri", which is when the menu shows.
export function isTypingCommand(text) {

  // [1] Test the text against the pattern
  const isTyping = TYPING_COMMAND_PATTERN.test(text || "");

  return isTyping;
}

// Writes the id of a row in the command menu.
export function buildOptionId(index) {

  // [1] Put the row number after the prefix
  const optionId = `${COMMAND_OPTION_ID_PREFIX}${index}`;

  return optionId;
}

// Works out which row to highlight after moving by one step, wrapping at both ends.
export function getSteppedIndex(index, step, length) {

  // [1] Move, then wrap round
  const steppedIndex = (index + step + length) % length;

  return steppedIndex;
}

// Works out how full today's token allowance is, from 0 to 100. Null when there is no token meter or the policy sets no token limit.
export function findTokenPercent(meters) {

  // [1] Find the token meter
  const meterList = Array.isArray(meters) ? meters : [];
  const meter = meterList.find((item) => item.limitType === LIMIT_TYPE_TOKENS);

  // [2] No meter, or no limit set, means nothing to show
  if (!meter || meter.max === null || meter.max === undefined) return null;

  // [3] A limit of nothing is full
  if (!meter.max) return TOKEN_FULL_PERCENT;

  // [4] Work out the share used, and never go past full
  const share = Math.round((Number(meter.used || 0) / Number(meter.max)) * TOKEN_FULL_PERCENT);
  const percent = Math.min(TOKEN_FULL_PERCENT, share);

  return percent;
}

// Picks the colour of the token readout: red when used up, amber when nearly, otherwise calm.
export function getTokenTone(percent) {

  // [1] Red when used up
  if (percent >= TOKEN_FULL_PERCENT) return TOKEN_TONE_BAD;

  // [2] Amber when nearly used up, otherwise calm
  if (percent >= TOKEN_WARN_PERCENT) return TOKEN_TONE_WARN;

  return TOKEN_TONE_OK;
}

// Writes how much of the ring is filled, as the dash pattern the ring needs: the filled length, then the whole length.
export function buildTokenDash(percent) {

  // [1] Work out the filled length of the ring
  const filledLength = (TOKEN_RING_LENGTH * percent) / TOKEN_FULL_PERCENT;

  // [2] Write the filled length, then the whole length
  const tokenDash = `${filledLength.toFixed(TOKEN_RING_DECIMALS)} ${TOKEN_RING_LENGTH}`;

  return tokenDash;
}
