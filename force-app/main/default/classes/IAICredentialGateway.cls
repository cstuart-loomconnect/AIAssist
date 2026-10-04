/*
Class Name: IAICredentialGateway

=================================================================
=================================================================

Description: What AICredentialSetupController needs from the platform to create and update External Credentials,
their stored key, and Named Credentials. The platform's own API for this (ConnectApi.NamedCredentials) cannot
be called from a test, so the controller talks to this interface: AICredentialGateway is the real thing and
a test supplies its own. The arguments are plain values, so a test double needs no ConnectApi types.

Public, not global: nothing outside the package implements it.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public interface IAICredentialGateway {
  Boolean externalCredentialExists(String developerName);

  // A Custom-protocol External Credential with one named principal and one custom header whose value is a formula reading the stored key.
  void createExternalCredential(
    String developerName,
    String label,
    String principalName,
    String headerName,
    String headerValue
  );

  // Whether the principal already has a stored key.
  Boolean credentialExists(String externalCredential, String principalName);

  // Stores the key against the principal: created the first time, updated (rotated) afterwards.
  void saveCredential(
    String externalCredential,
    String principalName,
    String parameterName,
    String secret,
    Boolean isUpdate
  );

  // The Id of the External Credential's named principal, which is what a permission set is given access to. Null when there is none.
  Id getPrincipalId(String externalCredential, String principalName);

  Boolean namedCredentialExists(String developerName);

  // A Named Credential for the URL, using the External Credential, with formulas allowed in headers and the package's namespace allowed to call it.
  void saveNamedCredential(
    String developerName,
    String label,
    String url,
    String externalCredential,
    String allowedNamespace,
    Boolean isUpdate
  );
}
