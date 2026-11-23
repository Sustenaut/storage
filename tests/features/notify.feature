Feature: Notices: the ingest pod is told of each file taken into a buffer's inbox, signed, after the answer
  The storage service (src/storage.js) with an R2 bucket in memory, and the ingest
  pod (integrations.sustenaut.eu) a fake service. A notice is POST /ingest/notify,
  {"tenant", "name", "size"}, signed with INGEST_NOTIFY_KEY: HMAC-SHA256 over the
  Unix seconds, a dot and the body (src/notify.js).

  Background:
    Given a scratch directory
    And the "GitHub's OIDC issuer" service publishes its test keys
    And the tenant "calls" is:
      """
      {"private": true, "inbox": true, "read": ["github:Sustenaut/ingest@refs/heads/main"],
       "write": ["github:Sustenaut/sender@refs/heads/main", "github:Sustenaut/ingest@refs/heads/main"],
       "delete": ["github:Sustenaut/ingest@refs/heads/main"]}
      """
    And a file "calls.avro" holding the bytes of "an Avro file of 5 bytes"
    And a file "batch.json" holding the bytes of "the text {}"
    And the "the ingest pod" service answers "POST /ingest/notify" with 202
    And requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"

  Scenario: A file taken into the inbox is told to the ingest pod, signed with the key
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And the ingest pod was told, signed with "k1", of:
      """
      [{"request": "POST /ingest/notify", "body": {"tenant": "calls", "name": "inbox/calls/2026-11-02/171800-web-abc.avro", "size": 5},
        "signed": true, "now": true}]
      """
    And 1 notice was sent to the ingest pod, with a timeout

  Scenario: The notice goes after the answer, handed to waitUntil with the call log's records
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    And requests are handled with a waitUntil
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And 1 promises were handed to waitUntil
    And 1 notice was sent to the ingest pod, with a timeout

  Scenario: The notices go where INGEST_NOTIFY_URL says
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    And the project's INGEST_NOTIFY_URL is "https://integrations.sustenaut.eu/elsewhere/notify"
    And the "the ingest pod" service answers "POST /elsewhere/notify" with 202
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the "the ingest pod" service was asked "POST /elsewhere/notify"

  Scenario: Without the key no one is told
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And nothing was sent to the ingest pod

  Scenario: Only the inbox is told of: not batch records, nor what is set aside
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    And requests carry a GitHub Actions token for "Sustenaut/ingest" at "refs/heads/main"
    When I send "PUT" to "/calls/batches/inbox_1.json" with the file "batch.json"
    And I send "PUT" to "/calls/rejected/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And nothing was sent to the ingest pod

  Scenario: A file storage refuses is told of to no one
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "batch.json"
    Then the answer is 400
    And nothing was sent to the ingest pod

  Scenario: A notice leaves no record for the call log
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    And the call log is bound
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then 1 notice was sent to the ingest pod, with a timeout
    And the call log was sent 0 batches

  Scenario Outline: The answer is the same whatever the ingest pod does with the notice
    Given the project's secret INGEST_NOTIFY_KEY is "k1"
    And <what>
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And the bucket holds 1 objects
    And the log says "storage: ingest didn't take the notice of calls/inbox/calls/2026-11-02/171800-web-abc.avro"

    Examples:
      | what                                                                |
      | the "the ingest pod" service can't be reached                       |
      | the "the ingest pod" service does not answer in time                |
