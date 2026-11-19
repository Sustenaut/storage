Feature: Files: a tenant's documents, stored under their content's SHA-256 and served with their type, for good
  The storage service (src/storage.js) with an R2 bucket in memory, GitHub a
  fake service, and the site's in_use list a fake service of its host's name.

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
    And GitHub lets the token push to "Sustenaut/business-plan"
    And GitHub knows the token as "schryer"

  Scenario: A file is stored under its content's SHA-256, with what its upload said
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "report" holding:
      | field | file     | content                 |
      | file  | file.bin | a PDF                   |
      | name  |          | market-report.pdf       |
      | label |          | OPP-02 market report v3 |
    When I send "POST" to "/opportunity/files" with the file "report"
    Then the answer is 200
    And the answer is the JSON:
      """
      {"id": "a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e", "name": "market-report.pdf",
       "url": "/opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/market-report.pdf",
       "type": "application/pdf", "size": 21, "label": "OPP-02 market report v3", "subject": "", "kept": false}
      """
    And the bucket's "opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/market-report.pdf" has the metadata "by" set to "schryer"
    And the bucket's "opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/market-report.pdf" has the metadata "label" set to "OPP-02 market report v3"

  Scenario: A stored file is served with its type, inline, sandboxed and cached for good
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "report" holding:
      | field | file     | content           |
      | file  | file.bin | a PDF             |
      | name  |          | market-report.pdf |
    And I have sent "POST" to "/opportunity/files" with the file "report", answered 200
    When I GET "/opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/market-report.pdf"
    Then the answer is 200
    And the answer's "Content-Type" is "application/pdf"
    And the answer's "Cache-Control" is "public, max-age=31536000, immutable"
    And the answer's "Content-Disposition" is 'inline; filename="market-report.pdf"'
    And the answer's "Content-Security-Policy" is "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox"

  Scenario: A file's own name is used when the upload names none, and an Office file downloads rather than opens
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "deck" holding:
      | field | file      | content                            |
      | file  | deck.pptx | the bytes 50 4b 03 04 00 00 00 00 |
    And I have sent "POST" to "/opportunity/files" with the file "deck", answered 200
    When I GET "/opportunity/f/c740f0ec5aff6078d92cd8843de452a73d41c5df00d238f5568b43dac4864740/deck.pptx"
    Then the answer is 200
    And the answer's "Content-Type" is "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    And the answer's "Content-Disposition" is 'attachment; filename="deck.pptx"'

  Scenario Outline: A file must be of a type the tenant allows, look like it, and fit: <name> holding <content>
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "file" holding:
      | field | file     | content   |
      | file  | file.bin | <content> |
      | name  |          | <name>    |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is <status>
    And the answer includes "<says>"
    And the bucket holds <stored> objects

    Examples:
      | name        | content                      | status | says                                                    | stored |
      | page.html   | a PDF                        | 415    | opportunity takes pdf, pptx, png, svg, csv, not .html   | 0      |
      | notes.docx  | a PDF                        | 415    | not .docx                                               | 0      |
      | fake.pdf    | an SVG                       | 400    | fake.pdf is not a .pdf file                             | 0      |
      | fake.pptx   | a PDF                        | 400    | fake.pptx is not a .pptx file                           | 0      |
      | big.pdf     | a PDF reading "x" 1000 times | 413    | big.pdf is over 1000 bytes                              | 0      |
      | ../evil.pdf | a PDF                        | 400    | the name is letters, digits, dots, dashes and underscores | 0    |
      | figure.svg  | an SVG                       | 200    | figure.svg                                              | 1      |

  Scenario: A field an upload doesn't take is refused
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
      | extra |          | x       |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 400
    And the answer includes "unexpected field extra"
    And the bucket holds 0 objects

  Scenario: A tenant without "files" refuses them
    Given GitHub lets the token push to "schryer/visit-ee"
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/visit-ee/files" with the file "file"
    Then the answer is 404
    And the answer includes "this site keeps no files here"

  Scenario: A tenant without "files" doesn't serve the path either
    When I GET "/visit-ee/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.pdf"
    Then the answer is 404
    And the answer includes "no such route"

  Scenario: A file upload without a token is refused
    Given the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 401
    And the answer includes "sign in first"
    And the bucket holds 0 objects

  Scenario: A token GitHub refuses can't upload a file
    Given GitHub answers 401 for the repository "Sustenaut/business-plan"
    And requests carry the header "Authorization" set to "Bearer bad"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 403
    And the bucket holds 0 objects

  Scenario: A token that can't push to the tenant's repository can't upload a file
    Given GitHub lets the token read but not push to "Sustenaut/business-plan"
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 403
    And the answer includes "that token can't write to Sustenaut/business-plan"
    And the bucket holds 0 objects

  Scenario: A GitHub App installation token uploads when its installation can write to the repository, for whom it says
    Given GitHub lists the installation's repositories:
      | repository              | push |
      | Sustenaut/business-plan | yes  |
    And requests carry the header "Authorization" set to "Bearer ghs_app"
    And the form "offer" holding:
      | field | file     | content           |
      | file  | file.bin | a PDF             |
      | name  |          | offer.pdf         |
      | kept  |          | true              |
      | for   |          | david@example.org |
    When I send "POST" to "/opportunity/files" with the file "offer"
    Then the answer is 200
    And the bucket's "opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/offer.pdf" has the metadata "by" set to "github-app"
    And the bucket's "opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/offer.pdf" has the metadata "for" set to "david@example.org"
    And the bucket's "opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/offer.pdf" has the metadata "kept" set to "true"
    And the "GitHub" service was asked "GET /installation/repositories?per_page=100&page=1" with the header "Authorization" set to "Bearer ghs_app"
    And the "GitHub" service was asked "GET /user" 0 times

  Scenario: A person's token can't claim to upload for someone else
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "mine" holding:
      | field | file     | content             |
      | file  | file.bin | a PDF reading "mine" |
      | name  |          | mine.pdf            |
      | for   |          | someone@example.org |
    When I send "POST" to "/opportunity/files" with the file "mine"
    Then the answer is 200
    And the bucket's "opportunity/f/64abae2c0603f70a106cc9711e56ce2897231ac332ba52a823d527f0016a0242/mine.pdf" has no metadata "for"

  Scenario: An installation token GitHub refuses can't upload
    Given GitHub answers 401 for the installation's repositories
    And requests carry the header "Authorization" set to "Bearer ghs_other"
    And the form "file" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 403
    And the answer includes "GitHub said 401 for the app's repositories"

  Scenario: An installation that can only read the repository can't upload
    Given GitHub lists the installation's repositories:
      | repository              | push |
      | Sustenaut/business-plan | no   |
    And requests carry the header "Authorization" set to "Bearer ghs_app"
    And the form "file" holding:
      | field | file     | content           |
      | file  | file.bin | a PDF reading "2" |
      | name  |          | b.pdf             |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 403
    And the answer includes "the app can't write to Sustenaut/business-plan"

  Scenario: An installation on other repositories only can't upload
    Given GitHub lists the installation's repositories:
      | repository       | push |
      | schryer/visit-ee | yes  |
    And requests carry the header "Authorization" set to "Bearer ghs_app"
    And the form "file" holding:
      | field | file     | content           |
      | file  | file.bin | a PDF reading "3" |
      | name  |          | c.pdf             |
    When I send "POST" to "/opportunity/files" with the file "file"
    Then the answer is 403
    And the answer includes "the app isn't installed on Sustenaut/business-plan"

  Scenario: An installation's earlier yes expires, and then a revoked permission is refused
    Given GitHub lists the installation's repositories:
      | repository              | push |
      | Sustenaut/business-plan | yes  |
    And requests carry the header "Authorization" set to "Bearer ghs_app"
    And the form "first" holding:
      | field | file     | content |
      | file  | file.bin | a PDF   |
      | name  |          | a.pdf   |
    And I have sent "POST" to "/opportunity/files" with the file "first", answered 200
    And GitHub lists the installation's repositories:
      | repository              | push |
      | Sustenaut/business-plan | no   |
    And 60 seconds have passed
    And the form "second" holding:
      | field | file     | content           |
      | file  | file.bin | a PDF reading "2" |
      | name  |          | b.pdf             |
    When I send "POST" to "/opportunity/files" with the file "second"
    Then the answer is 403
    And the "GitHub" service was asked "GET /installation/repositories" 2 times

  Scenario: The clean-up deletes old files no place uses, never kept ones, nor new ones
    Given the bucket already holds:
      | key                                                                                              | content | uploaded                 | kept  |
      | opportunity/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/used.pdf           | a PDF   | 2026-09-02T00:00:00.000Z | false |
      | opportunity/f/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/unused.pdf         | a PDF   | 2026-09-02T00:00:00.000Z | false |
      | opportunity/f/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/sent-to-client.pdf | a PDF   | 2025-10-27T00:00:00.000Z | true  |
      | opportunity/f/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/new.pdf            | a PDF   | 2026-11-29T00:00:00.000Z | false |
    And the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": []}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": [], "files": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}
      """
    When the clean-up runs at "2026-12-01T00:00:00Z"
    Then the result is:
      """
      {"visit-ee": {"deleted": []},
       "opportunity": {"deleted": ["opportunity/f/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/unused.pdf"]}}
      """
    And the bucket holds:
      """
      opportunity/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/used.pdf
      opportunity/f/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/sent-to-client.pdf
      opportunity/f/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/new.pdf
      """

  Scenario: A list without a "files" key has no file cleaned
    Given the bucket already holds:
      | key                                                                                              | content | uploaded                 | kept  |
      | opportunity/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/used.pdf           | a PDF   | 2026-09-02T00:00:00.000Z | false |
      | opportunity/f/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/sent-to-client.pdf | a PDF   | 2025-10-27T00:00:00.000Z | true  |
      | opportunity/f/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/new.pdf            | a PDF   | 2026-11-29T00:00:00.000Z | false |
    And the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": []}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": []}
      """
    When the clean-up runs at "2027-12-01T00:00:00Z"
    Then the result's "opportunity" is '{"deleted": []}'
    And the bucket holds 3 objects

  Scenario: An empty files list while files could go looks like a broken site, so the clean-up keeps them
    Given the bucket already holds:
      | key                                                                                              | content | uploaded                 | kept  |
      | opportunity/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/used.pdf           | a PDF   | 2026-09-02T00:00:00.000Z | false |
      | opportunity/f/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/sent-to-client.pdf | a PDF   | 2025-10-27T00:00:00.000Z | true  |
      | opportunity/f/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/new.pdf            | a PDF   | 2026-11-29T00:00:00.000Z | false |
    And the "temp.schryer.eu" service answers "GET /photos.json" with 200 and:
      """
      {"photos": []}
      """
    And the "opportunity.sustenaut.eu" service answers "GET /storage-in-use.json" with 200 and:
      """
      {"photos": [], "files": []}
      """
    When the clean-up runs at "2027-12-01T00:00:00Z"
    Then the result's "opportunity.skipped" is "https://opportunity.sustenaut.eu/storage-in-use.json lists no files"
    And the bucket holds 3 objects

  Scenario: A kept file stays kept when the same file is uploaded again
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "kept" holding:
      | field | file     | content   |
      | file  | file.bin | a PDF     |
      | name  |          | offer.pdf |
      | kept  |          | true      |
    And I have sent "POST" to "/opportunity/files" with the file "kept", answered 200
    And the form "again" holding:
      | field | file     | content   |
      | file  | file.bin | a PDF     |
      | name  |          | offer.pdf |
    When I send "POST" to "/opportunity/files" with the file "again"
    Then the answer is 200
    And the answer is the JSON:
      """
      {"id": "a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e", "name": "offer.pdf",
       "url": "/opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/offer.pdf",
       "type": "application/pdf", "size": 21, "label": "", "subject": "", "kept": true}
      """
    And the bucket's "opportunity/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/offer.pdf" has the metadata "kept" set to "true"
