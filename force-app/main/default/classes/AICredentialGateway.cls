/*
Class Name: AICredentialGateway

=================================================================
=================================================================

Description: The real IAICredentialGateway: a thin layer over ConnectApi.NamedCredentials and nothing else, so
that everything worth testing stays in AICredentialSetupController. ConnectApi.NamedCredentials cannot be
called from a test, so this class is not covered by one; it holds no decisions.

The key passes through saveCredential to the platform, which encrypts and stores it. It is not kept, logged
or returned here.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AICredentialGateway implements IAICredentialGateway {
  public Boolean externalCredentialExists(String developerName) {
    try {
      return ConnectApi.NamedCredentials.getExternalCredential(developerName) !=
        null;
    } catch (Exception notFound) {
      return false;
    }
  }

  public void createExternalCredential(
    String developerName,
    String label,
    String principalName,
    String headerName,
    String headerValue
  ) {
    ConnectApi.ExternalCredentialPrincipalInput principal = new ConnectApi.ExternalCredentialPrincipalInput();
    principal.principalName = principalName;
    principal.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
    principal.sequenceNumber = 1;

    ConnectApi.CredentialCustomHeaderInput header = new ConnectApi.CredentialCustomHeaderInput();
    header.headerName = headerName;
    header.headerValue = headerValue;
    header.sequenceNumber = 1;

    ConnectApi.ExternalCredentialInput input = new ConnectApi.ExternalCredentialInput();
    input.developerName = developerName;
    input.masterLabel = label;
    input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
    input.principals = new List<ConnectApi.ExternalCredentialPrincipalInput>{
      principal
    };
    input.customHeaders = new List<ConnectApi.CredentialCustomHeaderInput>{
      header
    };

    ConnectApi.NamedCredentials.createExternalCredential(input);
  }

  public Boolean credentialExists(
    String externalCredential,
    String principalName
  ) {
    try {
      ConnectApi.Credential stored = ConnectApi.NamedCredentials.getCredential(
        externalCredential,
        principalName,
        ConnectApi.CredentialPrincipalType.NamedPrincipal
      );
      return stored != null &&
        stored.credentials != null &&
        !stored.credentials.isEmpty();
    } catch (Exception notFound) {
      return false;
    }
  }

  public void saveCredential(
    String externalCredential,
    String principalName,
    String parameterName,
    String secret,
    Boolean isUpdate
  ) {
    ConnectApi.CredentialValueInput keyValue = new ConnectApi.CredentialValueInput();
    keyValue.value = secret;
    keyValue.encrypted = true;

    ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
    input.externalCredential = externalCredential;
    input.principalName = principalName;
    input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
    input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
    input.credentials = new Map<String, ConnectApi.CredentialValueInput>{
      parameterName => keyValue
    };

    if (isUpdate)
      ConnectApi.NamedCredentials.updateCredential(input);
    else
      ConnectApi.NamedCredentials.createCredential(input);
  }

  public Id getPrincipalId(String externalCredential, String principalName) {
    try {
      for (
        ConnectApi.ExternalCredentialPrincipal principal : ConnectApi.NamedCredentials.getExternalCredential(
            externalCredential
          )
          .principals
      ) {
        if (principal.principalName == principalName)
          return principal.id;
      }
    } catch (Exception notFound) {
      return null;
    }

    return null;
  }

  public Boolean namedCredentialExists(String developerName) {
    try {
      return ConnectApi.NamedCredentials.getNamedCredential(developerName) !=
        null;
    } catch (Exception notFound) {
      return false;
    }
  }

  public void saveNamedCredential(
    String developerName,
    String label,
    String url,
    String externalCredential,
    String allowedNamespace,
    Boolean isUpdate
  ) {
    ConnectApi.ExternalCredentialInput linkedCredential = new ConnectApi.ExternalCredentialInput();
    linkedCredential.developerName = externalCredential;

    // The key reaches the provider through a header formula, so formulas must be allowed in headers and the platform must not add an Authorization header of its own.
    ConnectApi.NamedCredentialCalloutOptionsInput calloutOptions = new ConnectApi.NamedCredentialCalloutOptionsInput();
    calloutOptions.allowMergeFieldsInBody = false;
    calloutOptions.allowMergeFieldsInHeader = true;
    calloutOptions.generateAuthorizationHeader = false;

    ConnectApi.NamedCredentialInput input = new ConnectApi.NamedCredentialInput();
    input.developerName = developerName;
    input.masterLabel = label;
    input.type = ConnectApi.NamedCredentialType.SecuredEndpoint;
    input.calloutUrl = url;
    input.externalCredentials = new List<ConnectApi.ExternalCredentialInput>{
      linkedCredential
    };
    input.calloutOptions = calloutOptions;

    // Managed code may call a subscriber's Named Credential only when its namespace is allowed on it.
    if (String.isNotBlank(allowedNamespace)) {
      ConnectApi.NamedCredentialParameterInput namespaceParameter = new ConnectApi.NamedCredentialParameterInput();
      namespaceParameter.parameterName = 'AllowedManagedPackageNamespaces';
      namespaceParameter.parameterType = ConnectApi.NamedCredentialParameterType.AllowedManagedPackageNamespaces;
      namespaceParameter.parameterValue = allowedNamespace;
      input.parameters = new List<ConnectApi.NamedCredentialParameterInput>{
        namespaceParameter
      };
    }

    if (isUpdate)
      ConnectApi.NamedCredentials.updateNamedCredential(developerName, input);
    else
      ConnectApi.NamedCredentials.createNamedCredential(input);
  }
}
