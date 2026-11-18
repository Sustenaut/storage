Feature: The plane tenant, as tenants.json has it: each plane repository's main writes a head another reads, and others can't
  The storage service (src/storage.js) with tenants.json's tenants, an R2
  bucket in memory, and GitHub's OIDC issuer a fake service publishing a key
  made for the tests. {"a":1} is stored under
  015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862.

  Background:
    Given a scratch directory
    And the "GitHub's OIDC issuer" service publishes its test keys
    And every tenant of tenants.json

  Scenario: A plane repository's main stores a file in the plane tenant
    Given requests carry a GitHub Actions token for "Sustenaut/observability" at "refs/heads/main"
    And the form "state" holding:
      | field | file       | content          |
      | file  | state.json | the text {"a":1} |
    When I send "POST" to "/plane/files" with the file "state"
    Then the answer is 200
    And the answer includes '"id":"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'

  Scenario: Another plane repository's main moves a head to it
    Given the bucket already holds:
      | key                                                                                 | content          |
      | plane/f/015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862/state.json | the text {"a":1} |
    And requests carry a GitHub Actions token for "Sustenaut/notifier" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/plane/head/board" with:
      """
      {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"}
      """
    Then the answer is 200

  Scenario Outline: Every plane repository's main reads the head: <repository>
    Given the bucket already holds:
      | key                                                                                 | content          |
      | plane/f/015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862/state.json | the text {"a":1} |
    And "Sustenaut/notifier" has moved the head "board" of "plane" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "Sustenaut/<repository>" at "refs/heads/main"
    When I GET "/plane/head/board"
    Then the answer is 200
    And the answer includes '{"a":1}'

    Examples:
      | repository           |
      | observability        |
      | notifier             |
      | integrations         |
      | release-controlplane |
      | opportunity-site     |
      | notebooks            |
      | auth                 |

  Scenario Outline: Nobody else reads the plane's head: <repository> at <ref>
    Given the bucket already holds:
      | key                                                                                 | content          |
      | plane/f/015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862/state.json | the text {"a":1} |
    And "Sustenaut/notifier" has moved the head "board" of "plane" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "<repository>" at "<ref>"
    When I GET "/plane/head/board"
    Then the answer is 403

    Examples:
      | repository         | ref                |
      | Sustenaut/stranger | refs/heads/main    |
      | Sustenaut/notifier | refs/heads/feature |

  Scenario: No token reads the plane's head
    When I GET "/plane/head/board"
    Then the answer is 401

  Scenario Outline: Nobody else writes the plane: <repository> at <ref>
    Given requests carry a GitHub Actions token for "<repository>" at "<ref>"
    And the form "state" holding:
      | field | file       | content     |
      | file  | state.json | the text {} |
    When I send "POST" to "/plane/files" with the file "state"
    Then the answer is 403
    And the bucket holds 0 objects

    Examples:
      | repository              | ref                |
      | Sustenaut/stranger      | refs/heads/main    |
      | Sustenaut/observability | refs/heads/feature |

  Scenario Outline: The plane keeps JSON of at most a megabyte: <name> holding <content>
    Given requests carry a GitHub Actions token for "Sustenaut/observability" at "refs/heads/main"
    And the form "state" holding:
      | field | file   | content   |
      | file  | <name> | <content> |
    When I send "POST" to "/plane/files" with the file "state"
    Then the answer is <status>
    And the bucket holds 0 objects

    Examples:
      | name       | content                     | status |
      | state.pdf  | the text {}                 | 415    |
      | state.json | the text "x" 1048577 times  | 413    |
