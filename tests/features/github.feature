Feature: Asking GitHub: its yeses kept a minute, a timeout on every call, and each call a record for the call log
  The storage service (src/storage.js) with an R2 bucket in memory, GitHub a
  fake service, and the call log's Durable Object binding kept in memory.

  Background:
    Given a scratch directory
    And the time is "2026-11-01T00:00:00Z"
    And the tenant "visit-ee" is:
      """
      {"repository": "schryer/visit-ee", "origins": ["https://temp.schryer.eu"], "in_use": "https://temp.schryer.eu/photos.json"}
      """
    And the tenant "opportunity" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": ["https://opportunity.sustenaut.eu"],
       "in_use": "https://opportunity.sustenaut.eu/storage-in-use.json",
       "files": {"types": ["pdf", "pptx", "png", "svg", "csv"], "max_bytes": 1000}}
      """
    And GitHub lets the token push to "schryer/visit-ee"
    And GitHub lets the token push to "Sustenaut/business-plan"
    And GitHub knows the token as "schryer"
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "photo" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x360 JPEG |

  Scenario: GitHub's yes is kept a minute, so another upload with the same token doesn't ask again
    Given I have sent "POST" to "/visit-ee/upload" with the file "photo", answered 200
    And 59 seconds have passed
    And the form "another" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x361 JPEG |
    When I send "POST" to "/visit-ee/upload" with the file "another"
    Then the answer is 200
    And the "GitHub" service was asked "GET /repos/schryer/visit-ee" 1 times
    And the "GitHub" service was asked "GET /user" 1 times
    And it sent 2 requests, each with a timeout
    And the bucket's "visit-ee/p/92dc4770b32c290f/480.jpg" has the metadata "by" set to "schryer"
    And the bucket's "visit-ee/p/b00742bee0a029fe/480.jpg" has the metadata "by" set to "schryer"

  Scenario: The same token for another repository is asked about on its own
    Given I have sent "POST" to "/visit-ee/upload" with the file "photo", answered 200
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 200
    And the "GitHub" service was asked "GET /repos/Sustenaut/business-plan" 1 times
    And the "GitHub" service was asked "GET /user" 2 times
    And it sent 4 requests, each with a timeout

  Scenario: A kept yes expires after a minute, and then a revoked permission is refused
    Given I have sent "POST" to "/visit-ee/upload" with the file "photo", answered 200
    And GitHub lets the token read but not push to "schryer/visit-ee"
    And 60 seconds have passed
    And the form "another" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x361 JPEG |
    When I send "POST" to "/visit-ee/upload" with the file "another"
    Then the answer is 403
    And it sent 3 requests, each with a timeout

  Scenario: A no is never kept: GitHub is asked again at once
    Given GitHub lets the token read but not push to "schryer/visit-ee"
    And I have sent "POST" to "/visit-ee/upload" with the file "photo", answered 403
    And GitHub lets the token push to "schryer/visit-ee"
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And the "GitHub" service was asked "GET /repos/schryer/visit-ee" 2 times

  Scenario: An installation's refusal is never kept either
    Given GitHub answers 401 for the installation's repositories
    And requests carry the header "Authorization" set to "Bearer ghs_other"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    And I have sent "POST" to "/opportunity/files" with the file "file", answered 403
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 403
    And the "GitHub" service was asked "GET /installation/repositories" 2 times

  Scenario: The cache is keyed by a hash of the token and repository, never the token
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And the kept yeses are:
      """
      [["c53fc219ef9ba39efac1ec6c3407792eb9cc913195f381219916972569cb6aae", {"login": "schryer", "app": false, "until": 1793491260000}]]
      """

  Scenario: The cache holds at most a thousand yeses, dropping the oldest
    Given the cache already keeps 1000 yeses for other tokens
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And 1000 yeses are kept
    And no yes is kept as "k0"

  Scenario: GitHub not answering in time is a 503, not a refusal, and isn't kept
    Given the "GitHub" service does not answer in time
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 503
    And the answer includes "GitHub didn't answer within 10 s; try again"
    And 0 yeses are kept
    And it sent 1 requests, each with a timeout

  Scenario: GitHub not answering an installation token in time is a 503 too
    Given the "GitHub" service does not answer in time
    And requests carry the header "Authorization" set to "Bearer ghs_app"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 503
    And 0 yeses are kept
    And it sent 1 requests, each with a timeout

  Scenario: GitHub that can't be reached at all is a 503 too
    Given the "GitHub" service can't be reached
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 503
    And the answer includes "GitHub can't be reached: fetch failed"

  Scenario: The clean-up's in_use lists have a timeout, and one that times out is skipped
    Given the "temp.schryer.eu" service does not answer in time
    And the "opportunity.sustenaut.eu" service does not answer in time
    When the clean-up runs
    Then the result is:
      """
      {"visit-ee": {"skipped": "https://temp.schryer.eu/photos.json: The operation timed out."},
       "opportunity": {"skipped": "https://opportunity.sustenaut.eu/storage-in-use.json: The operation timed out."}}
      """
    And it sent 2 requests, each with a timeout

  Scenario: A call a person waits on is of the class tried once, within 10 s
    When the call policy "H" is read
    Then the result's "timeout" is "10"
    And the result's "tries" is "1"

  Scenario: Each call to GitHub is a record of github.repo-ops check-push, without the token
    Given the call log is bound
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And the call log was sent 1 batches
    And the call log was sent the records:
      | object  | url                      | sender  | repo    | app    | plugin          | operation  | status | outcome |
      | storage | https://call-log/records | storage | storage | worker | github.repo-ops | check-push | 200    | ok      |
      | storage | https://call-log/records | storage | storage | worker | github.repo-ops | check-push | 200    | ok      |
    And nothing sent to the call log includes "good"

  Scenario: GitHub failing is tried once, as a person waits on it
    Given GitHub answers 502 for the repository "schryer/visit-ee"
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 503
    And the answer includes "GitHub said 502; try again"
    And the "GitHub" service was asked "GET /repos/schryer/visit-ee" 1 times

  Scenario: A request's records go to the call log in one call, handed to waitUntil so the answer doesn't wait
    Given the call log is bound
    And requests are handled with a waitUntil
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And 1 promises were handed to waitUntil
    And the call log was sent 1 batches
    And the call log was sent the records:
      | plugin          | operation  |
      | github.repo-ops | check-push |
      | github.repo-ops | check-push |

  Scenario: A request that made no calls sends the call log nothing
    Given the call log is bound
    And requests are handled with a waitUntil
    When I GET "/nope"
    Then the answer is 404
    And 1 promises were handed to waitUntil
    And the call log was sent 0 batches

  Scenario: Without the binding the records are let go, and nothing is written to the bucket
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And no records wait to be sent to the call log
    And the bucket holds:
      """
      visit-ee/p/92dc4770b32c290f/480.jpg
      """
