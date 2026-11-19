Feature: Buffers: files in folders, sent, read, listed and deleted by the principals a tenant's lists name
  The storage service (src/storage.js) with an R2 bucket in memory that lists
  as R2 does, and GitHub's OIDC issuer a fake service publishing a key made for
  the tests.

  Background:
    Given a scratch directory
    And the "GitHub's OIDC issuer" service publishes its test keys
    And the tenant "calls" is:
      """
      {"private": true, "inbox": true, "read": ["github:Sustenaut/reader@refs/heads/main"],
       "write": ["github:Sustenaut/sender@refs/heads/main", "github:Sustenaut/ingest@refs/heads/main"],
       "delete": ["github:Sustenaut/ingest@refs/heads/main"]}
      """
    And the tenant "other" is:
      """
      {"private": true, "inbox": true, "read": [], "write": ["github:Sustenaut/stranger@refs/heads/main"], "delete": []}
      """
    And the tenant "plain" is:
      """
      {"private": true, "read": [], "write": ["github:Sustenaut/sender@refs/heads/main"]}
      """
    And the tenant "open" is:
      """
      {"inbox": true, "repository": "o/r", "write": ["github:Sustenaut/sender@refs/heads/main"]}
      """
    And a file "calls.avro" holding the bytes of "an Avro file of 5 bytes"

  Scenario: A sender stores a file
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And the answer is the JSON:
      """
      {"name": "inbox/calls/2026-11-02/171800-web-abc.avro", "size": 5}
      """

  Scenario: A reader reads a stored file back, uncached
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And I have sent "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro", answered 200
    And requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/calls/inbox/calls/2026-11-02/171800-web-abc.avro"
    Then the answer is 200
    And the answer's "Content-Type" is "application/avro"
    And the answer's "Cache-Control" is "private, no-store"
    And the answer's bytes are "4f 62 6a 01 07"

  Scenario: A reader asks for a stored file with HEAD
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And I have sent "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro", answered 200
    And requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I send "HEAD" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro"
    Then the answer is 200

  Scenario: A file not stored is not found
    Given requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/calls/inbox/calls/none.avro"
    Then the answer is 404

  Scenario: Sending a name again replaces the file, so a retry is safe
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And I have sent "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro", answered 200
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 200
    And the bucket holds 1 objects

  Scenario Outline: A file must be what its folder holds: <path> holding <content>
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And a file "body" holding the bytes of '<content>'
    When I send "PUT" to "<path>" with the file "body"
    Then the answer is <status>

    Examples:
      | path                                              | content                 | status |
      | /calls/inbox/calls/2026-11-02/171800-web-abc.avro | the text not avro       | 400    |
      | /calls/batches/job.json                           | the text {not json      | 400    |
      | /calls/batches/job.json                           | the text {"files":[]}   | 200    |
      | /calls/rejected/calls/a.avro                      | an Avro file of 5 bytes | 200    |

  Scenario Outline: A name outside the folders, or a way out of them, isn't a buffer's: <path>
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    When I send "PUT" to "<path>" with the file "calls.avro"
    Then the answer is <status>
    And the bucket holds 0 objects

    Examples:
      | path                         | status |
      | /calls/inbox/a.json          | 404    |
      | /calls/batches/a.avro        | 404    |
      | /calls/other/a.avro          | 404    |
      | /calls/inbox/../a.avro       | 404    |
      | /calls/inbox/.hidden/a.avro  | 404    |

  Scenario: A file over the limit is refused
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And a file "big.avro" holding the bytes of "an Avro file of 52428801 bytes"
    When I send "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "big.avro"
    Then the answer is 413
    And the bucket holds 0 objects

  Scenario: Listing gives the oldest name first, a page at a time
    Given the bucket already holds:
      | key                                          | content                 |
      | calls/inbox/calls/2026-11-02/171800-b.avro   | an Avro file of 5 bytes |
      | calls/inbox/calls/2026-11-02/171600-a.avro   | an Avro file of 5 bytes |
      | calls/inbox/calls/2026-11-02/172000-c.avro   | an Avro file of 5 bytes |
      | calls/rejected/calls/x.avro                  | an Avro file of 5 bytes |
    And requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/calls/list?prefix=inbox/&limit=2"
    Then the answer is 200
    And the answer includes '"name":"inbox/calls/2026-11-02/171600-a.avro","size":5'
    And the answer includes '"name":"inbox/calls/2026-11-02/171800-b.avro","size":5'
    And the answer does not include "172000-c"
    And the answer does not include "rejected"
    And the answer includes '"cursor":"2"'

  Scenario: The next page of a listing is the rest, and the last says so
    Given the bucket already holds:
      | key                                          | content                 |
      | calls/inbox/calls/2026-11-02/171800-b.avro   | an Avro file of 5 bytes |
      | calls/inbox/calls/2026-11-02/171600-a.avro   | an Avro file of 5 bytes |
      | calls/inbox/calls/2026-11-02/172000-c.avro   | an Avro file of 5 bytes |
      | calls/rejected/calls/x.avro                  | an Avro file of 5 bytes |
    And requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/calls/list?prefix=inbox/&limit=2&cursor=2"
    Then the answer is 200
    And the answer includes '"name":"inbox/calls/2026-11-02/172000-c.avro"'
    And the answer does not include "171600-a"
    And the answer includes '"cursor":null'

  Scenario Outline: A listing is only of a buffer's folders, with a sensible limit: <query>
    Given requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/calls/list?<query>"
    Then the answer is 400

    Examples:
      | query                  |
      | prefix=f/              |
      | prefix=                |
      | prefix=inbox/../       |
      | prefix=inbox/&limit=0  |
      | prefix=inbox/&limit=1001 |
      | prefix=inbox/&limit=x  |

  Scenario Outline: Only the delete list may delete, and writing or reading isn't enough: <repository>
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And I have sent "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro", answered 200
    And requests carry a GitHub Actions token for "<repository>" at "refs/heads/main"
    When I send "DELETE" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro"
    Then the answer is 403
    And the bucket holds 1 objects

    Examples:
      | repository       |
      | Sustenaut/sender |
      | Sustenaut/reader |

  Scenario: The delete list deletes
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    And I have sent "PUT" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro", answered 200
    And requests carry a GitHub Actions token for "Sustenaut/ingest" at "refs/heads/main"
    When I send "DELETE" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro"
    Then the answer is 204
    And the bucket holds 0 objects

  Scenario: A person's token can't delete
    Given the bucket already holds:
      | key                                            | content                 |
      | calls/inbox/calls/2026-11-02/171800-web-abc.avro | an Avro file of 5 bytes |
    And requests carry the header "Authorization" set to "Bearer ghp_x"
    When I send "DELETE" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro"
    Then the answer is 401
    And the bucket holds 1 objects

  Scenario Outline: No token can't do anything: <method> <path>
    Given the bucket already holds:
      | key                                            | content                 |
      | calls/inbox/calls/2026-11-02/171800-web-abc.avro | an Avro file of 5 bytes |
    When I send "<method>" to "<path>" with the file "calls.avro"
    Then the answer is 401

    Examples:
      | method | path                                              |
      | PUT    | /calls/inbox/calls/2026-11-02/171800-web-abc.avro |
      | DELETE | /calls/inbox/calls/2026-11-02/171800-web-abc.avro |

  Scenario Outline: No token can't read anything: <path>
    Given the bucket already holds:
      | key                                            | content                 |
      | calls/inbox/calls/2026-11-02/171800-web-abc.avro | an Avro file of 5 bytes |
    When I GET "<path>"
    Then the answer is 401

    Examples:
      | path                                              |
      | /calls/inbox/calls/2026-11-02/171800-web-abc.avro |
      | /calls/list?prefix=inbox/                         |

  Scenario Outline: One project's writers can't reach another's buffer: <method> <path>
    Given the bucket already holds:
      | key                                            | content                 |
      | calls/inbox/calls/2026-11-02/171800-web-abc.avro | an Avro file of 5 bytes |
    And requests carry a GitHub Actions token for "Sustenaut/stranger" at "refs/heads/main"
    When I send "<method>" to "<path>" with the file "calls.avro"
    Then the answer is 403
    And the bucket holds 1 objects

    Examples:
      | method | path                                              |
      | PUT    | /calls/inbox/calls/2026-11-02/171800-web-abc.avro |
      | DELETE | /calls/inbox/calls/2026-11-02/171800-web-abc.avro |

  Scenario Outline: One project's writers can't read another's buffer: <path>
    Given requests carry a GitHub Actions token for "Sustenaut/stranger" at "refs/heads/main"
    When I GET "<path>"
    Then the answer is 403

    Examples:
      | path                                              |
      | /calls/inbox/calls/2026-11-02/171800-web-abc.avro |
      | /calls/list?prefix=inbox/                         |

  Scenario: A sender can't write another project's buffer
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    When I send "PUT" to "/other/inbox/a.avro" with the file "calls.avro"
    Then the answer is 403
    And the bucket holds 0 objects

  Scenario Outline: A tenant without a buffer, or a public one, has none of this: <method> <path>
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    When I send "<method>" to "<path>" with the file "calls.avro"
    Then the answer is 404
    And the bucket holds 0 objects

    Examples:
      | method | path                |
      | PUT    | /plain/inbox/a.avro |
      | PUT    | /open/inbox/a.avro  |

  Scenario: A public tenant has no listing
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    When I GET "/open/list?prefix=inbox/"
    Then the answer is 404

  Scenario: Other methods on a buffer's file aren't allowed
    Given requests carry a GitHub Actions token for "Sustenaut/sender" at "refs/heads/main"
    When I send "POST" to "/calls/inbox/calls/2026-11-02/171800-web-abc.avro" with the file "calls.avro"
    Then the answer is 405
