Feature: tenants.json: who reads and writes each tenant, and what it keeps

  Scenario: The opportunity tenant takes the files the opportunity site needs, read by the opportunity app
    When tenants.json's "opportunity" is read
    Then the result's "private" is "true"
    And the result's "read" is '["k8s:opportunity/app"]'
    And the result's "repository" is "Sustenaut/business-plan"
    And the result's "origins" is '["https://opportunity.sustenaut.eu"]'
    And the result's "files.types" is '["pdf", "pptx", "docx", "png", "jpg", "svg", "csv", "xlsx"]'

  Scenario: The opportunity tenant takes the opportunity app's pod token, and editors' GitHub tokens still work
    When tenants.json's "opportunity" is read
    Then the result's "write" is '["k8s:opportunity/app"]'
    And the result's "repository" is "Sustenaut/business-plan"

  Scenario Outline: The opportunity tenant's write list takes the opportunity app's account and no other: <principal>
    When "<principal>" is matched against the list '["k8s:opportunity/app"]'
    Then the result is "<matches>"

    Examples:
      | principal               | matches |
      | k8s:opportunity/app     | true    |
      | k8s:opportunity/default | false   |
      | k8s:auth/app            | false   |

  Scenario: The visit-ee tenant keeps photos only
    When tenants.json's "visit-ee" is read
    Then the result does not include "files"

  Scenario: The pdc tenant is public, and only pub-site's main writes it: kept signed objects and their reading data, never cleaned
    When tenants.json's "pdc" is read
    Then the result does not include "private"
    And the result does not include "repository"
    And the result's "write" is '["github:Sustenaut/pub-site@refs/heads/main"]'
    And the result's "files" is '{"types": ["cbor", "json"], "max_bytes": 26214400, "kept": true}'
    And the result does not include "in_use"

  Scenario: The facts tenant is private: business-plan's editors upload, its main reads, kept, signed objects only
    When tenants.json's "facts" is read
    Then the result's "private" is "true"
    And the result's "editors" is "true"
    And the result's "repository" is "Sustenaut/business-plan"
    And the result's "read" is '["github:Sustenaut/business-plan@refs/heads/main"]'
    And the result's "files.types" is '["cbor"]'
    And the result's "files.kept" is "true"
    And the result does not include "public_types"

  Scenario: The sources tenant is private: business-plan's main and the review pod read it, its editors upload and move its heads, only raw papers are public, kept and never cleaned
    When tenants.json's "sources" is read
    Then the result's "private" is "true"
    And the result's "editors" is "true"
    And the result's "public_types" is '["pdf"]'
    And the result's "read" is '["github:Sustenaut/business-plan@refs/heads/main", "k8s:review/app"]'
    And the result's "heads" is "true"
    And the result's "repository" is "Sustenaut/business-plan"
    And the result does not include "in_use"
    And the result's "files" is '{"types": ["pdf", "cbor", "json"], "max_bytes": 26214400, "kept": true}'

  Scenario: The publications tenant is private: business-plan's main writes it, pub-site, estimate and the review pod read it, kept
    When tenants.json's "publications" is read
    Then the result's "private" is "true"
    And the result's "write" is '["github:Sustenaut/business-plan@refs/heads/main"]'
    And the result's "read" is '["github:Sustenaut/pub-site", "github:Sustenaut/estimate", "k8s:review/app"]'
    And the result's "heads" is "true"
    And the result's "files.types" is '["gz"]'
    And the result's "files.kept" is "true"
    And the result does not include "in_use"
    And the result's "editors" is "true"
    And the result's "repository" is "Sustenaut/business-plan"

  Scenario: The wheels tenant is public, kept, never cleaned, and only storage's own main writes it
    When tenants.json's "wheels" is read
    Then the result does not include "private"
    And the result does not include "repository"
    And the result's "write" is '["github:Sustenaut/storage@refs/heads/main"]'
    And the result's "files" is '{"types": ["whl"], "max_bytes": 26214400, "kept": true}'
    And the result does not include "in_use"

  Scenario: The terraform tenant is public, kept, never cleaned, serves the mirror protocol, and only storage's own main writes it
    When tenants.json's "terraform" is read
    Then the result does not include "private"
    And the result does not include "repository"
    And the result's "providers" is "true"
    And the result's "write" is '["github:Sustenaut/storage@refs/heads/main"]'
    And the result's "files" is '{"types": ["zip"], "max_bytes": 104857600, "kept": true}'
    And the result does not include "in_use"

  Scenario: The pypi tenant is public, kept, never cleaned, serves a simple index, and only storage's own main writes it
    When tenants.json's "pypi" is read
    Then the result does not include "private"
    And the result does not include "repository"
    And the result's "simple" is "true"
    And the result's "write" is '["github:Sustenaut/storage@refs/heads/main"]'
    And the result's "files" is '{"types": ["whl", "gz", "zip"], "max_bytes": 104857600, "kept": true}'
    And the result does not include "in_use"

  Scenario Outline: Each release tenant is read by its own deployment alone: <tenant>
    When tenants.json's "<tenant>" is read
    Then the result's "private" is "true"
    And the result's "heads" is "true"
    And the result's "write" is '["<writer>"]'
    And the result's "read" is '["<reader>"]'
    And the result's "files.types" is '["json"]'
    And the result's "files.kept" is "true"
    And the result does not include "repository"

    Examples:
      | tenant            | writer                                               | reader                  |
      | release-sustenaut | github:Sustenaut/release-controlplane@refs/heads/main | k8s:release/app         |
      | release-schryer   | github:schryer/release-controlplane@refs/heads/main   | k8s:release-schryer/app |

  Scenario Outline: One deployment's token can't read the other's tenant: <principal> on <tenant>
    When tenants.json's "<tenant>" is asked whether it lists "<principal>" as a reader or writer
    Then the result is "false"

    Examples:
      | tenant            | principal                                             |
      | release-sustenaut | k8s:release-schryer/app                               |
      | release-schryer   | k8s:release/app                                       |
      | release-sustenaut | github:schryer/release-controlplane@refs/heads/main   |
      | release-schryer   | github:Sustenaut/release-controlplane@refs/heads/main |

  Scenario: The plane tenant is read and written by each plane repository's main and the convergence engine alone
    When tenants.json's "plane" is read
    Then the result's "private" is "true"
    And the result's "heads" is "true"
    And the result's "read" is '["github:Sustenaut/observability@refs/heads/main", "github:Sustenaut/notifier@refs/heads/main", "github:Sustenaut/integrations@refs/heads/main", "github:Sustenaut/release-controlplane@refs/heads/main", "github:Sustenaut/opportunity-site@refs/heads/main", "github:Sustenaut/notebooks@refs/heads/main", "github:Sustenaut/auth@refs/heads/main", "k8s:convergence/app"]'
    And the result's "write" is '["github:Sustenaut/observability@refs/heads/main", "github:Sustenaut/notifier@refs/heads/main", "github:Sustenaut/integrations@refs/heads/main", "github:Sustenaut/release-controlplane@refs/heads/main", "github:Sustenaut/opportunity-site@refs/heads/main", "github:Sustenaut/notebooks@refs/heads/main", "github:Sustenaut/auth@refs/heads/main", "k8s:convergence/app"]'
    And the result's "files" is '{"types": ["json"], "max_bytes": 1048576, "kept": true}'
    And the result does not include "repository"

  Scenario: The calls-storage tenant is the call log's buffer: only ingest reads, writes or deletes through the API
    When tenants.json's "calls-storage" is read
    Then the result is:
      """
      {"private": true, "inbox": true, "read": ["k8s:integrations/ingest"], "write": ["k8s:integrations/ingest"], "delete": ["k8s:integrations/ingest"]}
      """

  Scenario Outline: The convergence engine's buffers, only it and ingest write: <tenant>
    When tenants.json's "<tenant>" is read
    Then the result is:
      """
      {"private": true, "inbox": true, "read": ["k8s:integrations/ingest"],
       "write": ["k8s:convergence/app", "k8s:integrations/ingest"], "delete": ["k8s:integrations/ingest"]}
      """

    Examples:
      | tenant                   |
      | need-states              |
      | calls-convergence-engine |

  Scenario: The calls-release-controlplane tenant is a call-log buffer both release deployments write
    When tenants.json's "calls-release-controlplane" is read
    Then the result is:
      """
      {"private": true, "inbox": true, "read": ["k8s:integrations/ingest"],
       "write": ["k8s:release/app", "k8s:release-schryer/app", "k8s:integrations/ingest"], "delete": ["k8s:integrations/ingest"]}
      """

  Scenario: Every buffer's deleter may also write and read it, to record its loads and move a file that won't load
    When the deleters of tenants.json's buffers are looked up
    Then the result's "problems" is "[]"
    And the result's "found" is "true"

  Scenario: The pinned k3s key set is the server's: an issuer and RSA signing keys
    When src/k8s.json is read
    Then the result's "issuer" is "https://kubernetes.default.svc.cluster.local"
    And the result's "kinds" is '["RSA"]'
    And the result's "hasKeys" is "true"
