Feature: Named heads: the latest of something in a private tenant, moved only from where it points
  The storage service (src/storage.js) with an R2 bucket in memory that writes
  conditionally as R2 does, and GitHub's OIDC issuer a fake service publishing
  a key made for the tests. The files a head points at are stored under their
  hashes:

    {"a":1}  015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862
    {"b":1}  eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3
    {"c":1}  a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e
    {}       44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a

  Background:
    Given a scratch directory
    And the time is "2026-10-30T10:00:00Z"
    And the "GitHub's OIDC issuer" service publishes its test keys
    And the tenant "snaps" is:
      """
      {"private": true, "heads": true, "read": ["github:Sustenaut/reader"],
       "write": ["github:Sustenaut/release-controlplane@refs/heads/main"], "files": {"types": ["json"], "kept": true}}
      """
    And the tenant "noheads" is:
      """
      {"private": true, "read": [], "write": ["github:Sustenaut/release-controlplane@refs/heads/main"], "files": {"types": ["json"], "kept": true}}
      """
    And the tenant "open" is:
      """
      {"repository": "o/r", "heads": true, "write": ["github:Sustenaut/release-controlplane@refs/heads/main"], "files": {"types": ["json"]}}
      """
    And the bucket already holds:
      | key                                                                          | content          |
      | snaps/f/015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862/board.json | the text {"a":1} |
      | snaps/f/eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3/board.json | the text {"b":1} |
      | snaps/f/a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e/board.json | the text {"c":1} |
      | snaps/f/44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a/board.json | the text {}      |

  Scenario: A head's first move takes If-None-Match: *, and answers its place with the hash as the ETag
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"}
      """
    Then the answer is 200
    And the answer's "ETag" is '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    And the answer is the JSON:
      """
      {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862",
       "key": "snaps/f/015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862/board.json",
       "time": "2026-10-30T10:00:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"}
      """

  Scenario: A head serves the file it points at, with its hash as the ETag, uncached
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/snaps/head/board"
    Then the answer is 200
    And the answer includes '{"a":1}'
    And the answer is the JSON:
      """
      {"a": 1}
      """
    And the answer's "ETag" is '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    And the answer's "Content-Type" is "application/json"
    And the answer's "Cache-Control" is "private, no-store"
    And the answer's "Content-Security-Policy" is "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox"

  Scenario: HEAD gives the hash without the file
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I send "HEAD" to "/snaps/head/board"
    Then the answer is 200
    And the answer's "ETag" is '"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"'
    And the answer has no body

  Scenario Outline: A head that has never moved is not found: <path>
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I GET "<path>"
    Then the answer is 404

    Examples:
      | path                  |
      | /snaps/head/board     |
      | /snaps/head/board/log |

  Scenario: A head that has never moved takes no move without If-None-Match: *
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
      """
    Then the answer is 412
    And the answer includes "board has never moved: send If-None-Match: *"

  Scenario: A head that has never moved takes no move from a place
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
      """
    Then the answer is 412

  Scenario Outline: Moving needs the current hash, and answers 412 otherwise: <condition> set to <value>
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "<condition>" set to '<value>'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"}
      """
    Then the answer is <status>

    Examples:
      | condition     | value                                                              | status |
      | If-None-Match | *                                                                  | 412    |
      | If-Match      | "a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e" | 412    |
      | If-Match      | "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862" | 200    |
      | If-Match      | 015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862   | 200    |

  Scenario: Moving a head that has moved, without saying from where, answers 412
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"}
      """
    Then the answer is 412
    And the answer includes "board points at 015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"

  Scenario: A place the head has left is no longer current
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e"}
      """
    Then the answer is 412
    And the bucket's "snaps/h/board" includes '"hash":"eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"'

  Scenario: A head points where its last move put it
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I GET "/snaps/head/board"
    Then the answer's "ETag" is '"eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"'

  Scenario: If-Match takes a weak hash as well as a quoted or bare one
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to 'W/"eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e"}
      """
    Then the answer is 200

  Scenario: Of two moves from the same place, only one wins
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And "Sustenaut/release-controlplane" moves the head "board" of "snaps" to "a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e" just before the next move writes it
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"}
      """
    Then the answer is 412
    And the answer includes "board moved just now"
    And the bucket's "snaps/h/board" includes '"hash":"a1dd48c657971696c2087f2a6beb489ee65b25320b763222f10718dd93e9149e"'

  Scenario: Of two first moves at once, only one wins
    Given "Sustenaut/release-controlplane" moves the head "board" of "snaps" to "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3" just before the next move writes it
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"}
      """
    Then the answer is 412
    And the bucket's "snaps/h/board" includes '"hash":"eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"'

  Scenario: The log lists every place, newest first, with time and principal
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And 60 seconds have passed
    And "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"
    And 60 seconds have passed
    And "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "Sustenaut/reader" at "refs/heads/main"
    When I GET "/snaps/head/board/log"
    Then the answer is 200
    And the answer's "Cache-Control" is "private, no-store"
    And the answer is the JSON:
      """
      {"name": "board", "log": [
        {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862", "time": "2026-10-30T10:02:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"},
        {"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3", "time": "2026-10-30T10:01:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"},
        {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862", "time": "2026-10-30T10:00:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"}
      ]}
      """

  Scenario: A move the bucket fails to write is a 500, and leaves the head where it was
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And the bucket's writes to keys ending "/h/board" fail
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"}
      """
    Then the answer is 500
    And the answer includes "the bucket is down"
    And the bucket's "snaps/h/board" includes '"hash":"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'

  Scenario: A move that failed adds nothing false to the log
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And the bucket's writes to keys ending "/h/board" fail
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    And a file "to-b" holding '{"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"}'
    And I have sent "PUT" to "/snaps/head/board" with the file "to-b", answered 500
    When I GET "/snaps/head/board/log"
    Then the answer is the JSON:
      """
      {"name": "board", "log": [
        {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862", "time": "2026-10-30T10:00:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"}
      ]}
      """

  Scenario: After a move that failed, the next one moves the head and logs where it was, once
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And the bucket's writes to keys ending "/h/board" fail
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"'
    And a file "to-b" holding '{"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3"}'
    And I have sent "PUT" to "/snaps/head/board" with the file "to-b", answered 500
    And the bucket's writes work again
    And I have sent "PUT" to "/snaps/head/board" with the file "to-b", answered 200
    When I GET "/snaps/head/board/log"
    Then the answer is the JSON:
      """
      {"name": "board", "log": [
        {"hash": "eb8ed3ccb5023093b56f490a46501e88d09736687e609fdbc1c71b3df8b9ccd3", "time": "2026-10-30T10:00:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"},
        {"hash": "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862", "time": "2026-10-30T10:00:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"}
      ]}
      """

  Scenario: Moving to where it already points changes nothing
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-Match" set to '"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"'
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
      """
    Then the answer is 200
    And the bucket holds 5 objects

  Scenario: A move to where it already points adds nothing to the log
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    And "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I GET "/snaps/head/board/log"
    Then the answer is the JSON:
      """
      {"name": "board", "log": [
        {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", "time": "2026-10-30T10:00:00.000Z", "principal": "github:Sustenaut/release-controlplane@refs/heads/main"}
      ]}
      """

  Scenario: A head can only point at a stored file
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "0000000000000000000000000000000000000000000000000000000000000000"}
      """
    Then the answer is 404
    And the answer includes "no stored file has the hash"
    And the bucket holds 4 objects

  Scenario Outline: A move's body names a stored file's hash, which <body> doesn't
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    And a file "body" holding '<body>'
    When I send "PUT" to "/snaps/head/board" with the file "body"
    Then the answer is 400
    And the answer includes "sha256 of a stored file"
    And the bucket holds 4 objects

    Examples:
      | body            |
      | {}              |
      | not json        |
      | null            |
      | {"hash":"../x"} |
      | {"hash":1}      |

  Scenario Outline: Each name is its own head: <path> is not found
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I GET "<path>"
    Then the answer is 404

    Examples:
      | path                    |
      | /snaps/head/other       |
      | /snaps/head/Bad%20Name  |
      | /snaps/head/board/log/x |

  Scenario: A head's log is not moved
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/snaps/head/board/log" with:
      """
      {}
      """
    Then the answer is 404
    And the answer includes "no such route"

  Scenario Outline: Only the write list's principal, at its ref, moves a head: <repository> at <ref>
    Given requests carry a GitHub Actions token for "<repository>" at "<ref>"
    And requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
      """
    Then the answer is 403
    And the answer includes "may not write here"

    Examples:
      | repository                     | ref               |
      | Sustenaut/reader               | refs/heads/main   |
      | Sustenaut/release-controlplane | refs/heads/other  |

  Scenario: No token moves a head
    Given requests carry the header "If-None-Match" set to "*"
    When I send "PUT" to "/snaps/head/board" with:
      """
      {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
      """
    Then the answer is 401

  Scenario Outline: Only readers read a head: <path> for a stranger
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    And requests carry a GitHub Actions token for "Sustenaut/stranger" at "refs/heads/main"
    When I GET "<path>"
    Then the answer is 403

    Examples:
      | path                  |
      | /snaps/head/board     |
      | /snaps/head/board/log |

  Scenario: No token reads a head
    Given "Sustenaut/release-controlplane" has moved the head "board" of "snaps" to "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    When I GET "/snaps/head/board"
    Then the answer is 401

  Scenario Outline: A tenant without heads, or a public one, has none: <method> <path>
    Given the bucket already holds:
      | key                                                                                   | content     |
      | noheads/f/44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a/board.json | the text {} |
    And requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    And requests carry the header "If-None-Match" set to "*"
    When I send "<method>" to "<path>" with:
      """
      {"hash": "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"}
      """
    Then the answer is 404
    And the answer includes "this tenant has no heads"

    Examples:
      | method | path                |
      | PUT    | /noheads/head/board |
      | PUT    | /open/head/board    |

  Scenario: A tenant without heads has no head to read
    Given requests carry a GitHub Actions token for "Sustenaut/release-controlplane" at "refs/heads/main"
    When I GET "/noheads/head/board"
    Then the answer is 404
    And the answer includes "this tenant has no heads"

  Scenario: A public tenant has no head to read, even for anyone
    When I GET "/open/head/board"
    Then the answer is 404
