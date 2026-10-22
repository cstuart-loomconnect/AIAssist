/*
Component Name: aiPoliciesAssignments

=================================================================
=================================================================

Description: The Assignments tab of one policy: who gets it, how a user's policy is chosen and a box to check a user.

Step 1: Show a row for each user or permission set the policy is assigned to
Step 2: Tell the tab when the admin adds, switches or removes an assignment
Step 3: Show how a user's policy is chosen, and the Check a user box
Step 4: Pass on a request to assign a policy to a user, and check the user again on request

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { EVENT_ADD_REQUEST, EVENT_ACTIVE_CHANGE, EVENT_REMOVE, EVENT_ASSIGN_USER, CHECK_USER_SELECTOR, LABELS } from "./aiPoliciesAssignmentsSettings";
import { buildAssignmentViews } from "./aiPoliciesAssignmentsHelper";

// The Assignments tab of one policy. The tab passes the assignments and listens for what the admin does.
export default class AiPoliciesAssignments extends LightningElement {

  // Values passed in by the parent component
  @api policyId; // The policy these assignments belong to
  @api assignments = []; // [{ assignmentId, assigneeType, assigneeName, assigneeDetail, usersCovered, isActive }]

  // Values the template reads
  labels = LABELS;

  // The assignments turned into table rows.
  get assignmentViews() {

    // [1] Hand the work to the helper
    const assignmentViews = buildAssignmentViews(this.assignments);

    return assignmentViews;
  }

  get hasAssignments() {

    // [1] The table shows only when there is a row to show
    const hasAssignments = this.assignmentViews.length > 0;

    return hasAssignments;
  }

  // Asks the Check a user box to work out its answer again.
  @api
  refreshCheck() {

    // [1] Find the box and ask it
    const checkUser = this.template.querySelector(CHECK_USER_SELECTOR);
    if (checkUser) checkUser.refresh();
  }

  // Event handlers
  handleAddAssignment() {

    // [1] Tell the tab to open the Add assignment dialog
    this.dispatchEvent(new CustomEvent(EVENT_ADD_REQUEST));
  }

  handleActiveChange(event) {

    // [1] Tell the tab which assignment was switched, and to what
    const assignmentId = event.target.dataset.id;
    const isActive = event.target.checked;
    this.dispatchEvent(new CustomEvent(EVENT_ACTIVE_CHANGE, { detail: { assignmentId, isActive } }));
  }

  handleRemove(event) {

    // [1] Tell the tab which assignment to remove
    const assignmentId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent(EVENT_REMOVE, { detail: { assignmentId } }));
  }

  handleAssignUser(event) {

    // [1] Pass the request from the Check a user box on to the tab
    this.dispatchEvent(new CustomEvent(EVENT_ASSIGN_USER, { detail: event.detail }));
  }
}
