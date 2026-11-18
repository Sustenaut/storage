Feature: A private tenant's files, listed for its readers a page at a time, with what their uploads said of them, such as a subject
  The storage service (src/storage.js) with an R2 bucket in memory that lists
  as R2 does (custom metadata only when asked), and GitHub a fake service.

  Background:
    Given a scratch directory
    And the time is "2026-11-01T00:00:00Z"
    And the tenant "deals" is:
      """
      {"private": true, "editors": true, "repository": "o/deals", "origins": [], "files": {"types": ["pdf"]}}
      """
    And the tenant "calls" is:
      """
      {"private": true, "inbox": true, "read": [], "write": []}
      """
    And the tenant "closed" is:
      """
      {"private": true, "read": [], "write": []}
      """
    And the tenant "open" is:
      """
      {"repository": "o/open", "origins": [], "files": {"types": ["pdf"]}}
      """
    And GitHub lets the token push to "o/deals"
    And GitHub lets the token push to "o/open"
    And GitHub knows the token as "an-editor"
    And requests carry the header "Authorization" set to "Bearer editor"

  Scenario: An upload may name its subject
    Given the form "offer" holding:
      | field   | file      | content                   |
      | file    | offer.pdf | a PDF reading "offer.pdf" |
      | label   |           | The offer                 |
      | subject |           | card-42                   |
      | kept    |           | true                      |
    When I send "POST" to "/deals/files" with the file "offer"
    Then the answer is 200
    And the answer includes '"subject":"card-42"'

  Scenario: A reader lists the tenant's files with what their uploads said
    Given the form "offer" holding:
      | field   | file      | content                   |
      | file    | offer.pdf | a PDF reading "offer.pdf" |
      | label   |           | The offer                 |
      | subject |           | card-42                   |
      | kept    |           | true                      |
    And I have sent "POST" to "/deals/files" with the file "offer", answered 200
    And the form "notes" holding:
      | field | file      | content                   |
      | file  | notes.pdf | a PDF reading "notes.pdf" |
    And I have sent "POST" to "/deals/files" with the file "notes", answered 200
    When I GET "/deals/list?prefix=f/"
    Then the answer is 200
    And the answer's "Cache-Control" is "private, no-store"
    And the answer is the JSON:
      """
      {"files": [
        {"name": "notes.pdf", "id": "13b1304b4684d9c1814c0eb442ea3dfeb0cef43ed12105338b46472055ebcac8",
         "url": "/deals/f/13b1304b4684d9c1814c0eb442ea3dfeb0cef43ed12105338b46472055ebcac8/notes.pdf", "size": 24,
         "uploaded": "2026-11-01T00:00:00.000Z", "metadata": {"kept": "false", "by": "an-editor"}},
        {"name": "offer.pdf", "id": "bf3138616508a05adf6efbe500c649b35601b0101a2654289df1886690308694",
         "url": "/deals/f/bf3138616508a05adf6efbe500c649b35601b0101a2654289df1886690308694/offer.pdf", "size": 24,
         "uploaded": "2026-11-01T00:00:00.000Z", "metadata": {"label": "The offer", "kept": "true", "by": "an-editor", "subject": "card-42"}}
      ], "cursor": null}
      """
    And the bucket was last listed with:
      """
      {"prefix": "deals/f/", "limit": 1000, "include": ["customMetadata"]}
      """

  Scenario: A subject is cut to the label's length
    Given the form "a" holding:
      | field   | file  | content |
      | file    | a.pdf | a PDF reading "a.pdf" |
      | subject |       | "  ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss  " |
    When I send "POST" to "/deals/files" with the file "a"
    Then the answer is 200
    And the answer includes '"subject":"ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss"'
    And the bucket's "deals/f/d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d/a.pdf" has the metadata "subject" set to "ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss"

  Scenario: A subject is kept only when given
    Given the form "b" holding:
      | field | file  | content               |
      | file  | b.pdf | a PDF reading "b.pdf" |
    When I send "POST" to "/deals/files" with the file "b"
    Then the answer is 200
    And the bucket's "deals/f/8fffe26fc4b4757be3656fdf339523f92c80371c946d87345abf0ac2be320482/b.pdf" has no metadata "subject"

  Scenario: A listing comes a page at a time
    Given the bucket already holds:
      | key                                                                            | content               |
      | deals/f/d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d/a.pdf | a PDF reading "a.pdf" |
      | deals/f/8fffe26fc4b4757be3656fdf339523f92c80371c946d87345abf0ac2be320482/b.pdf | a PDF reading "b.pdf" |
      | deals/f/3f40d018af0371f9183501a3876b59426e9fb5942ff417ba86bf8e2dd3d18da4/c.pdf | a PDF reading "c.pdf" |
    When I GET "/deals/list?prefix=f/&limit=2"
    Then the answer is 200
    And the answer includes '"id":"3f40d018af0371f9183501a3876b59426e9fb5942ff417ba86bf8e2dd3d18da4"'
    And the answer includes '"id":"8fffe26fc4b4757be3656fdf339523f92c80371c946d87345abf0ac2be320482"'
    And the answer does not include "d00550687ea1cb46"
    And the answer includes '"cursor":"2"'

  Scenario: The last page of a listing is the rest, and says so
    Given the bucket already holds:
      | key                                                                            | content               |
      | deals/f/d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d/a.pdf | a PDF reading "a.pdf" |
      | deals/f/8fffe26fc4b4757be3656fdf339523f92c80371c946d87345abf0ac2be320482/b.pdf | a PDF reading "b.pdf" |
      | deals/f/3f40d018af0371f9183501a3876b59426e9fb5942ff417ba86bf8e2dd3d18da4/c.pdf | a PDF reading "c.pdf" |
    When I GET "/deals/list?prefix=f/&limit=2&cursor=2"
    Then the answer is 200
    And the answer includes '"id":"d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d"'
    And the answer does not include "8fffe26fc4b4757b"
    And the answer does not include "3f40d018af0371f9"
    And the answer includes '"cursor":null'

  Scenario: A prefix narrows a listing to an id
    Given the bucket already holds:
      | key                                                                            | content               |
      | deals/f/d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d/a.pdf | a PDF reading "a.pdf" |
      | deals/f/8fffe26fc4b4757be3656fdf339523f92c80371c946d87345abf0ac2be320482/b.pdf | a PDF reading "b.pdf" |
    When I GET "/deals/list?prefix=f/d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d/"
    Then the answer is 200
    And the answer includes '"id":"d00550687ea1cb46f220e71e9511001be884a754f7ede1a58b930bae7034f39d"'
    And the answer does not include "8fffe26fc4b4757b"

  Scenario: A prefix may be the start of an id
    When I GET "/deals/list?prefix=f/d00550"
    Then the answer is 200

  Scenario: Without a token nothing is listed
    Given requests carry the header "Authorization" set to "Bearer "
    When I GET "/deals/list?prefix=f/"
    Then the answer is 401

  Scenario: A token that can't push lists nothing
    Given GitHub lets the token read but not push to "o/deals"
    And requests carry the header "Authorization" set to "Bearer reader-only"
    When I GET "/deals/list?prefix=f/"
    Then the answer is 403

  Scenario: A token GitHub doesn't know lists nothing
    Given GitHub answers 404 for the repository "o/deals"
    And requests carry the header "Authorization" set to "Bearer nobody"
    When I GET "/deals/list?prefix=f/"
    Then the answer is 403

  Scenario Outline: A prefix outside f/, a bad one, or a bad limit is refused: <query>
    When I GET "/deals/list?<query>"
    Then the answer is <status>

    Examples:
      | query                                                                                     | status |
      | prefix=                                                                                   | 404    |
      | prefix=inbox/                                                                             | 404    |
      | prefix=f/../                                                                              | 400    |
      | prefix=f/xyz                                                                              | 400    |
      | prefix=f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa                 | 400    |
      | prefix=f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/../x             | 400    |
      | prefix=f/&limit=0                                                                         | 400    |
      | prefix=f/&limit=1001                                                                      | 400    |
      | prefix=f/&limit=x                                                                         | 400    |

  Scenario Outline: A public tenant is never listed, nor a private one's files without "files": <tenant>
    When I GET "/<tenant>/list?prefix=f/"
    Then the answer is 404
    And the bucket was never listed

    Examples:
      | tenant |
      | open   |
      | closed |

  Scenario: A buffer without files still takes only its folders, and asks for a token first
    Given requests carry the header "Authorization" set to "Bearer "
    When I GET "/calls/list?prefix=f/"
    Then the answer is 401
    And the bucket was never listed
