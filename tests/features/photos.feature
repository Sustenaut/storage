Feature: Photos: an editor's uploads, named by their content and served for good, and the clean-up of the ones no place uses
  The storage service (src/storage.js) with an R2 bucket in memory, GitHub a
  fake service, and the sites' in_use lists fake services of their hosts' names.

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
    And GitHub knows the token as "schryer"
    And requests come from "https://temp.schryer.eu"

  Scenario: An editor's upload is stored and named by its largest JPEG's content
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "photo" holding:
      | field    | file     | content        |
      | 480.jpg  | 480.jpg  | a 480x360 JPEG |
      | 960.jpg  | 960.jpg  | a 960x720 JPEG |
      | 480.webp | 480.webp | a WebP         |
      | 960.webp | 960.webp | a WebP         |
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 200
    And the answer's "Access-Control-Allow-Origin" is "https://temp.schryer.eu"
    And the answer is the JSON:
      """
      {"id": "73b81ff39a84b420", "width": 960, "height": 720, "widths": [480, 960], "formats": ["webp", "jpg"]}
      """
    And the bucket holds:
      """
      visit-ee/p/73b81ff39a84b420/480.jpg
      visit-ee/p/73b81ff39a84b420/480.webp
      visit-ee/p/73b81ff39a84b420/960.jpg
      visit-ee/p/73b81ff39a84b420/960.webp
      """
    And the bucket's "visit-ee/p/73b81ff39a84b420/960.jpg" has the metadata "by" set to "schryer"
    And the "GitHub" service was asked "GET /repos/schryer/visit-ee" with the header "Authorization" set to "Bearer good"

  Scenario: An uploaded photo is served with its type, cached for good
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "photo" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x360 JPEG |
      | 960.jpg | 960.jpg | a 960x720 JPEG |
    And I have sent "POST" to "/visit-ee/upload" with the file "photo", answered 200
    When I GET "/visit-ee/p/73b81ff39a84b420/960.jpg"
    Then the answer is 200
    And the answer's "Content-Type" is "image/jpeg"
    And the answer's "Cache-Control" is "public, max-age=31536000, immutable"

  Scenario: A token GitHub refuses can't upload
    Given GitHub answers 401 for the repository "schryer/visit-ee"
    And requests carry the header "Authorization" set to "Bearer bad"
    And the form "photo" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x360 JPEG |
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 403
    And the answer includes "GitHub said 401 for schryer/visit-ee"
    And the bucket holds 0 objects

  Scenario: A token that may only read the repository can't upload
    Given GitHub lets the token read but not push to "schryer/visit-ee"
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "photo" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x360 JPEG |
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 403
    And the answer includes "that token can't write to schryer/visit-ee"
    And the bucket holds 0 objects

  Scenario: An upload without a token is refused before anything is asked
    Given the form "photo" holding:
      | field   | file    | content        |
      | 480.jpg | 480.jpg | a 480x360 JPEG |
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is 401
    And the bucket holds 0 objects
    And the "GitHub" service was asked nothing

  Scenario Outline: An upload must be photos of allowed sizes: <part> holding <content> is refused
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "photo" holding:
      | field  | file   | content   |
      | <part> | <part> | <content> |
    When I send "POST" to "/visit-ee/upload" with the file "photo"
    Then the answer is <status>
    And the answer includes "<error>"
    And the bucket holds 0 objects

    Examples:
      | part      | content                                | status | error                       |
      | 480.jpg   | the text <svg/>                        | 400    | 480.jpg is not a jpg        |
      | 4000.jpg  | a 4000x3000 JPEG                       | 400    | 4000.jpg: wider than 1600   |
      | evil.html | a 480x360 JPEG                         | 400    | unexpected field evil.html  |
      | 480.jpg   | a 480x360 JPEG padded by 3250586 bytes | 413    | 480.jpg is over 3145728 bytes |

  Scenario: A JPEG's size comes from its frame header
    When the size of "a 1600x1067 JPEG" is read
    Then the result is:
      """
      {"width": 1600, "height": 1067}
      """

  Scenario: The clean-up deletes old photos no place uses, and keeps one in use and one that may be in an open pull request
    Given the bucket already holds:
      | key                                  | content        | uploaded                 |
      | visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg  | a 480x360 JPEG | 2026-09-02T00:00:00.000Z |
      | visit-ee/p/bbbbbbbbbbbbbbbb/480.jpg  | a 480x360 JPEG | 2026-09-02T00:00:00.000Z |
      | visit-ee/p/cccccccccccccccc/480.jpg  | a 480x360 JPEG | 2026-11-28T00:00:00.000Z |
    And the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": ["aaaaaaaaaaaaaaaa"]}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": [], "files": []}
      """
    When the clean-up runs at "2026-12-01T00:00:00Z"
    Then the result is:
      """
      {"visit-ee": {"deleted": ["visit-ee/p/bbbbbbbbbbbbbbbb/480.jpg"]}, "opportunity": {"deleted": []}}
      """
    And the bucket holds:
      """
      visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg
      visit-ee/p/cccccccccccccccc/480.jpg
      """

  Scenario: An empty list while photos exist looks like a broken site, so the clean-up keeps them all
    Given the bucket already holds:
      | key                                  | content        | uploaded                 |
      | visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg  | a 480x360 JPEG | 2026-09-02T00:00:00.000Z |
      | visit-ee/p/cccccccccccccccc/480.jpg  | a 480x360 JPEG | 2026-11-28T00:00:00.000Z |
    And the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": []}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": [], "files": []}
      """
    When the clean-up runs at "2027-12-01T00:00:00Z"
    Then the result is:
      """
      {"visit-ee": {"deleted": [], "skipped": "https://temp.schryer.eu/photos.json lists no photos"}, "opportunity": {"deleted": []}}
      """
    And the bucket holds 2 objects

  Scenario: The nightly clean-up, called, cleans
    Given the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": ["aaaaaaaaaaaaaaaa"]}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": [], "files": []}
      """
    When I send "POST" to "/_clean"
    Then the answer is 200
    And the answer is the JSON:
      """
      {"visit-ee": {"deleted": []}, "opportunity": {"deleted": []}}
      """

  Scenario: The clean-up runs once a day however often it is called
    Given the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": ["aaaaaaaaaaaaaaaa"]}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": [], "files": []}
      """
    And I have sent "POST" to "/_clean", answered 200
    When I send "POST" to "/_clean"
    Then the answer is 429
    And the answer includes "cleaned recently"
    And the "temp.schryer.eu" service was asked "GET /photos.json" 1 times

  Scenario Outline: Another site's paths, and a photo not stored, are not found: <path>
    When I GET "<path>"
    Then the answer is 404
    And the answer includes "not found"

    Examples:
      | path                                 |
      | /elsewhere/p/aaaaaaaaaaaaaaaa/480.jpg |
      | /visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg  |
