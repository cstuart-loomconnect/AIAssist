/*
Class Name: AIMessagingException

=================================================================
=================================================================

Description: The one exception the messaging layer throws to its callers.

getMessage() is always safe to show to the user (it comes from a Custom Label). Anything
technical - a DML error, a stack trace, a provider response - goes in detail, which is only
ever written to the platform log. code is a stable value from AIAssistApplicationConstants.ERROR_*
so the UI can react without parsing translated text.

isRefusal separates an expected "no" (limit reached, not assigned, terms not accepted) from
an unexpected failure. Refusals are not logged: a user hitting their daily limit is not an
error and would otherwise flood the log.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public class AIMessagingException extends Exception {
  public String code = AIAssistApplicationConstants.ERROR_GENERIC;
  public Boolean isRefusal = false;
  public String detail;

  // An expected refusal. userMessage must come from a Custom Label.
  public static AIMessagingException newRefusal(
    String code,
    String userMessage
  ) {
    AIMessagingException refusal = new AIMessagingException(userMessage);
    refusal.code = code;
    refusal.isRefusal = true;
    return refusal;
  }

  // An unexpected failure. The user only sees the generic label; detail is for the log.
  public static AIMessagingException newFailure(
    String detail,
    Exception cause
  ) {
    AIMessagingException failure = cause == null
      ? new AIMessagingException(Label.AI_Error_Generic)
      : new AIMessagingException(Label.AI_Error_Generic, cause);
    failure.detail = detail;
    return failure;
  }
}
