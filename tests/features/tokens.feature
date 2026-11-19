Feature: OpenID Connect tokens (src/jwt.js): whose they are, and which are refused
  GitHub's OIDC issuer and Google fake services publishing keys made for the
  tests, and the k3s server's keys pinned, as src/k8s.json pins the real one's,
  to a key made for the tests too.

  Background:
    Given the "GitHub's OIDC issuer" service publishes its test keys
    And the "Google" service publishes its test keys

  Scenario: A GitHub Actions token names its repository and ref
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    When the token is verified
    Then the result is "github:Sustenaut/business-plan@refs/heads/main"

  Scenario Outline: A GitHub Actions token is refused unless for this audience, in date and from a trusted issuer: its <claim> is <value>
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And its claim "<claim>" is "<value>"
    When the token is verified
    Then it is refused, saying "<says>"
    And the refusal's "status" is "401"

    Examples:
      | claim | value                         | says                                              |
      | aud   | sts.amazonaws.com             | refused: a token for another audience             |
      | exp   | now - 120                     | refused: an expired token                         |
      | nbf   | now + 600                     | refused: a token not valid yet                    |
      | iss   | https://token.actions.example | refused: an issuer this service doesn't trust     |
      | iss   | __proto__                     | refused: an issuer this service doesn't trust     |

  Scenario Outline: A GitHub Actions token without its <claim> is refused
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And it has no claim "<claim>"
    When the token is verified
    Then it is refused, saying "<says>"
    And the refusal's "status" is "401"

    Examples:
      | claim      | says                                     |
      | aud        | refused: a token for another audience    |
      | exp        | refused: an expired token                |
      | repository | refused: a token that doesn't say who it is |

  Scenario Outline: A token is refused unless RS256 and signed by a key of its issuer's: its header's <name> is <value>
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And its header's "<name>" is "<value>"
    When the token is verified
    Then it is refused, saying "<says>"
    And the refusal's "status" is "401"

    Examples:
      | name | value | says                                     |
      | alg  | HS256 | refused: tokens must be RS256            |
      | kid  | k2    | refused: a key this service doesn't know |

  Scenario: A token signed with another key is refused
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And it is signed with another key
    When the token is verified
    Then it is refused, saying "refused: a bad signature"
    And the refusal's "status" is "401"

  Scenario: An unsigned token is refused
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And it is sent unsigned, with the header '{"alg": "none"}'
    When the token is verified
    Then it is refused, saying "refused: tokens must be RS256"
    And the refusal's "status" is "401"

  Scenario: A token whose claims were changed under its signature is refused
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And its claims are swapped for:
      """
      {"iss": "https://token.actions.githubusercontent.com", "aud": "storage.sustenaut.eu",
       "repository": "Sustenaut/pub-site", "ref": "refs/heads/main", "exp": "now + 60"}
      """
    When the token is verified
    Then it is refused, saying "refused: a bad signature"
    And the refusal's "status" is "401"

  Scenario: Something that isn't a token is refused
    Given the token "not.a.token"
    When the token is verified
    Then it is refused, saying "refused: not a token"
    And the refusal's "status" is "401"

  Scenario: A minute of clock skew is allowed
    Given a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And its claim "exp" is "now - 30"
    When the token is verified
    Then the result is "github:Sustenaut/business-plan@refs/heads/main"

  Scenario: An audience list is taken when it includes this service
    Given a GitHub Actions token for "Sustenaut/pub-site" at "refs/heads/main"
    And its claim "aud" is '["other", "storage.sustenaut.eu"]'
    When the token is verified
    Then the result is "github:Sustenaut/pub-site@refs/heads/main"

  Scenario: The issuer's keys are fetched once
    Given a GitHub Actions token for "Sustenaut/pub-site" at "refs/heads/main"
    When the token is verified
    And the token is verified again
    Then the result is "github:Sustenaut/pub-site@refs/heads/main"
    And the "GitHub's OIDC issuer" service was asked "GET /.well-known/jwks" 1 times

  Scenario: A key the set lacks doesn't ask for the keys again within a minute
    Given the issuer's keys have been fetched
    And a GitHub Actions token for "Sustenaut/pub-site" at "refs/heads/main"
    And its header's "kid" is "new"
    When the token is verified
    Then it is refused, saying "refused: a key this service doesn't know"
    And the "GitHub's OIDC issuer" service was asked "GET /.well-known/jwks" 1 times

  Scenario: A key the set lacks asks for the keys again after a minute
    Given the issuer's keys have been fetched
    And a GitHub Actions token for "Sustenaut/pub-site" at "refs/heads/main"
    And its header's "kid" is "new"
    When the token is verified 2 minutes later
    Then it is refused, saying "refused: a key this service doesn't know"
    And the "GitHub's OIDC issuer" service was asked "GET /.well-known/jwks" 2 times

  Scenario: The keys are fetched again after ten minutes
    Given the issuer's keys have been fetched
    And a GitHub Actions token for "Sustenaut/pub-site" at "refs/heads/main"
    When the token is verified 13 minutes later
    Then it is refused, saying "refused: an expired token"
    And the "GitHub's OIDC issuer" service was asked "GET /.well-known/jwks" 2 times

  Scenario Outline: A principal matches a list entry by repository without case, and by ref when the entry names one: <list>
    When "github:Sustenaut/pub-site@refs/heads/main" is matched against the list '<list>'
    Then the result is "<matches>"

    Examples:
      | list                                          | matches |
      | ["github:Sustenaut/pub-site"]                 | true    |
      | ["github:sustenaut/PUB-SITE@refs/heads/main"] | true    |
      | ["github:Sustenaut/pub-site@refs/heads/Main"] | false   |
      | ["github:Sustenaut/pub"]                      | false   |
      | ["auth:Sustenaut/pub-site"]                   | false   |
      | []                                            | false   |

  Scenario: A principal matches no list when there is none
    When "github:Sustenaut/pub-site@refs/heads/main" is matched against no list
    Then the result is "false"

  Scenario Outline: GitHub tokens aren't taken for JWTs: <token>
    When "<token>" is taken for a JWT or not
    Then the result is "<jwt>"

    Examples:
      | token              | jwt   |
      | ghp_abc            | false |
      | ghs_abc            | false |
      | github_pat_11AB_cd | false |
      | gho_x              | false |
      | good               | false |
      | eyJh.eyJi.c2ln     | true  |

  # The k3s server's projected service-account tokens, against its pinned key set.

  Scenario: A pod's service-account token names its namespace and account, against the pinned keys, without fetching
    Given a pod token for the service account "app" of "opportunity"
    When the token is verified against the pinned keys of the k3s server
    Then the result is "k8s:opportunity/app"
    And it sent 0 requests, each with a timeout

  Scenario Outline: A pod's token is refused unless for this audience, in date and its account's: its <claim> is <value>
    Given a pod token for the service account "app" of "opportunity"
    And its claim "<claim>" is '<value>'
    When the token is verified against the pinned keys of the k3s server
    Then it is refused, saying "<says>"
    And the refusal's "status" is "401"

    Examples:
      | claim         | value                                                       | says                                        |
      | aud           | ["https://kubernetes.default.svc.cluster.local", "k3s"]     | refused: a token for another audience       |
      | exp           | now - 120                                                   | refused: an expired token                   |
      | sub           | system:serviceaccount:opportunity:default                   | refused: a token that doesn't say who it is |
      | kubernetes.io | {}                                                          | refused: a token that doesn't say who it is |

  Scenario: A pod's token signed with another key is refused
    Given a pod token for the service account "app" of "opportunity"
    And it is signed with another key
    When the token is verified against the pinned keys of the k3s server
    Then it is refused, saying "refused: a bad signature"
    And the refusal's "status" is "401"

  Scenario: A pod's token naming a key the pinned set lacks is refused
    Given a pod token for the service account "app" of "opportunity"
    And its header's "kid" is "k8s2"
    When the token is verified against the pinned keys of the k3s server
    Then it is refused, saying "refused: a key this service doesn't know"
    And the refusal's "status" is "401"

  Scenario: Another cluster has the same issuer name but not this key
    Given a pod token for the service account "app" of "opportunity"
    And it is signed with the key of GitHub's OIDC issuer
    When the token is verified against the pinned keys of the k3s server
    Then it is refused, saying "refused: a bad signature"
    And the refusal's "status" is "401"

  # Google identity tokens, as a Cloud Run service's metadata server gives them.

  Scenario Outline: A service account's identity token names its verified address: issued by <issuer>
    Given a Google identity token for "plan@sustenaut.iam.gserviceaccount.com"
    And its claim "iss" is "<issuer>"
    When the token is verified
    Then the result is "gcp:plan@sustenaut.iam.gserviceaccount.com"
    And the "Google" service was asked "GET /oauth2/v3/certs" 1 times
    And it sent 1 requests, each with a timeout

    Examples:
      | issuer                      |
      | https://accounts.google.com |
      | accounts.google.com         |

  Scenario Outline: A Google token for another audience, or out of date, is refused: its <claim> is <value>
    Given a Google identity token for "plan@sustenaut.iam.gserviceaccount.com"
    And its claim "<claim>" is "<value>"
    When the token is verified
    Then it is refused, saying "<says>"
    And the refusal's "status" is "401"

    Examples:
      | claim | value                        | says                                  |
      | aud   | https://someone-else.example | refused: a token for another audience |
      | exp   | now - 3600                   | refused: an expired token             |

  Scenario: A Google token not signed by Google is refused
    Given a Google identity token for "plan@sustenaut.iam.gserviceaccount.com"
    And it is signed with another key
    When the token is verified
    Then it is refused, saying "refused: a bad signature"
    And the refusal's "status" is "401"

  Scenario Outline: Only a verified service account's address is a principal: its <claim> is <value>
    Given a Google identity token for "plan@sustenaut.iam.gserviceaccount.com"
    And its claim "<claim>" is '<value>'
    When the token is verified
    Then it is refused, saying "refused: a token that doesn't say who it is"
    And the refusal's "status" is "401"

    Examples:
      | claim          | value                                          |
      | email_verified | false                                          |
      | email_verified | "true"                                         |
      | email          | someone@gmail.com                              |
      | email          | plan@sustenaut.iam.gserviceaccount.com.example |
      | email          | Plan@sustenaut.iam.gserviceaccount.com         |

  Scenario: A Google token without an address is refused
    Given a Google identity token for "plan@sustenaut.iam.gserviceaccount.com"
    And it has no claim "email"
    When the token is verified
    Then it is refused, saying "refused: a token that doesn't say who it is"
    And the refusal's "status" is "401"

  Scenario Outline: A tenant's list names Google accounts exactly, and an @ is never a ref: <principal> against <list>
    When "<principal>" is matched against the list '<list>'
    Then the result is "<matches>"

    Examples:
      | principal                                  | list                                           | matches |
      | gcp:plan@sustenaut.iam.gserviceaccount.com | ["gcp:plan@sustenaut.iam.gserviceaccount.com"] | true    |
      | gcp:other@sustenaut.iam.gserviceaccount.com | ["gcp:plan@sustenaut.iam.gserviceaccount.com"] | false   |
      | gcp:plan@sustenaut.iam.gserviceaccount.com | ["github:Sustenaut/business-plan"]             | false   |
      | gcp:plan@someone-else.iam.gserviceaccount.com | ["gcp:plan"]                                | false   |
      | k8s:opportunity/app@x                      | ["k8s:opportunity/app"]                        | false   |
