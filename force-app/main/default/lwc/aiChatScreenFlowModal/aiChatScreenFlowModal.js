import LightningModal from "lightning/modal";
import { api } from "lwc";

// Shows a Screen Flow action in a modal over the chat window, because the window is too narrow for a flow. lightning-flow runs the flow as the signed-in user, so the user's own permissions apply. Each outcome is reported as an "outcome" event (FINISHED or ERROR) for aiAssistChat to record; closing the modal at any time resolves the open() promise.
export default class AiChatScreenFlowModal extends LightningModal {
  @api label;
  @api flowApiName;
  @api inputVariables = [];

  handleStatusChange(event) {
    const status = event.detail.status;

    if (status === "FINISHED" || status === "FINISHED_SCREEN") {
      this.dispatchEvent(
        new CustomEvent("outcome", { detail: { outcome: "FINISHED" } })
      );
      // A flow with a finish screen stays open so the user can read it; one without closes itself.
      if (status === "FINISHED") this.close();
    } else if (status === "ERROR") {
      this.dispatchEvent(
        new CustomEvent("outcome", { detail: { outcome: "ERROR" } })
      );
    }
  }
}
