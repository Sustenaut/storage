Feature: A sources tenant: papers, publet objects and their index, all kept, private or partly public
  The storage service (src/storage.js) with an R2 bucket in memory and GitHub a fake service.

  Background:
    Given a scratch directory
    And the time is "2026-11-01T00:00:00Z"
    And the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true}}
      """
    And GitHub lets the token push to "Sustenaut/business-plan"
    And GitHub knows the token as "schryer"

  Scenario: A publet object is kept, and downloads as CBOR
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "object" holding:
      | field | file     | content         |
      | file  | file.bin | a CBOR map      |
      | name  |          | bafy-claim.cbor |
    When I send "POST" to "/sources/files" with the file "object"
    Then the answer is 200
    And the answer includes '"kept":true'
    And the bucket's "sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor" has the metadata "kept" set to "true"

  Scenario: A stored publet object downloads as CBOR
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "object" holding:
      | field | file     | content         |
      | file  | file.bin | a CBOR map      |
      | name  |          | bafy-claim.cbor |
    And I have sent "POST" to "/sources/files" with the file "object", answered 200
    When I GET "/sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor"
    Then the answer's "Content-Type" is "application/cbor"
    And the answer's "Content-Disposition" is 'attachment; filename="bafy-claim.cbor"'

  Scenario: An index is kept too, and shows as JSON
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "index" holding:
      | field | file     | content                     |
      | file  | file.bin | the text {"e.pump": "bafy"} |
      | name  |          | index.json                  |
    And I have sent "POST" to "/sources/files" with the file "index", answered 200
    When I GET "/sources/f/157becdf769304e91a38e9ea10eb0dcb13b4dd8fb4280ee8cb61a1fac18bddd2/index.json"
    Then the answer's "Content-Type" is "application/json"
    And the answer's "Content-Disposition" is 'inline; filename="index.json"'
    And the bucket's "sources/f/157becdf769304e91a38e9ea10eb0dcb13b4dd8fb4280ee8cb61a1fac18bddd2/index.json" has the metadata "kept" set to "true"

  Scenario: A paper is taken
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "paper" holding:
      | field | file     | content              |
      | file  | file.bin | a PDF                |
      | name  |          | diehl-cheng-2025.pdf |
    When I send "POST" to "/sources/files" with the file "paper"
    Then the answer is 200

  Scenario Outline: A cbor file must be a CBOR map and a json file must parse: <name> holding <content>
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "file" holding:
      | field | file     | content   |
      | file  | file.bin | <content> |
      | name  |          | <name>    |
    When I send "POST" to "/sources/files" with the file "file"
    Then the answer is <status>
    And the bucket holds 0 objects

    Examples:
      | name       | content               | status |
      | empty.cbor | nothing               | 400    |
      | array.cbor | the bytes 83 01 02 03 | 400    |
      | bad.json   | the text {not json    | 400    |
      | bytes.json | the bytes 7b ff 7d    | 400    |
      | page.html  | a CBOR map            | 415    |

  Scenario: A tenant without an in_use list has nothing cleaned
    Given the bucket already holds:
      | key                                                                            | content    | uploaded                 | kept  |
      | sources/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/old.cbor | a CBOR map | 2025-10-27T00:00:00.000Z | false |
    When the clean-up runs at "2026-12-01T00:00:00Z"
    Then the result is:
      """
      {"sources": {"skipped": "no in_use list: nothing is cleaned"}}
      """
    And the bucket holds 1 objects

  Scenario: An avro file that starts as Avro does is taken
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["avro"]}}
      """
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "calls" holding:
      | field | file       | content                  |
      | file  | calls.avro | the bytes 4f 62 6a 01 00 |
    When I send "POST" to "/sources/files" with the file "calls"
    Then the answer is 200

  Scenario: An avro file of another version is not Avro
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["avro"]}}
      """
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "calls" holding:
      | field | file       | content               |
      | file  | calls.avro | the bytes 4f 62 6a 02 |
    When I send "POST" to "/sources/files" with the file "calls"
    Then the answer is 400
    And the answer includes "calls.avro is not a .avro file"

  # A private tenant with editors takes a GitHub token that may push, for reading and writing, and is never public.

  Scenario: A private tenant with editors takes an upload with a GitHub token that may push
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true}
      """
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "object" holding:
      | field | file     | content         |
      | file  | file.bin | a CBOR map      |
      | name  |          | bafy-claim.cbor |
    When I send "POST" to "/sources/files" with the file "object"
    Then the answer is 200
    And the answer includes '"url":"/sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor"'

  Scenario: A private tenant with editors gives nothing without a token
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true}
      """
    And the bucket already holds:
      | key                                                                                          | content    |
      | sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor | a CBOR map |
    When I GET "/sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor"
    Then the answer is 401

  Scenario: A private tenant with editors gives nothing to a token that can't push
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true}
      """
    And the bucket already holds:
      | key                                                                                          | content    |
      | sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor | a CBOR map |
    And GitHub lets the token read but not push to "Sustenaut/business-plan"
    And requests carry the header "Authorization" set to "Bearer readonly"
    When I GET "/sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor"
    Then the answer is 403

  Scenario: A private tenant with editors gives an editor its files, never cached
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true}
      """
    And the bucket already holds:
      | key                                                                                          | content    |
      | sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor | a CBOR map |
    And requests carry the header "Authorization" set to "Bearer good"
    When I GET "/sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor"
    Then the answer is 200
    And the answer's "Cache-Control" is "private, no-store"

  Scenario: Without "editors" a private tenant takes no GitHub token
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true}
      """
    And the bucket already holds:
      | key                                                                                          | content    |
      | sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor | a CBOR map |
    And requests carry the header "Authorization" set to "Bearer good"
    When I GET "/sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor"
    Then the answer is 401
    And the answer includes "this tenant takes OpenID Connect tokens only"

  # A private tenant's public_types are open to anyone, and nothing else in it is.

  Scenario Outline: A private tenant's public type is open to anyone, and nothing else in it is: <name>
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true, "public_types": ["pdf"]}
      """
    And the bucket already holds:
      | key                                                                                          | content    |
      | sources/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/paper.pdf       | a PDF      |
      | sources/f/56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05/bafy-claim.cbor | a CBOR map |
      | sources/f/44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a/index.json      | the text {} |
    When I GET "/sources/f/<id>/<name>"
    Then the answer is <status>

    Examples:
      | id                                                               | name            | status |
      | 56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05 | bafy-claim.cbor | 401    |
      | 44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a | index.json      | 401    |
      | 56ca68e6aae1222049b647b1f2fd02c88306c920af4340d1fe02ebf961533a05 | bafy-claim.pdf  | 404    |

  Scenario: A private tenant's public paper is served to anyone, cached like a public tenant's
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true, "public_types": ["pdf"]}
      """
    And the bucket already holds:
      | key                                                                                    | content |
      | sources/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/paper.pdf | a PDF   |
    When I GET "/sources/f/a1ef702528f0a2e6bdf709acb3c19521fba134f5cd971404796d54f6e65d687e/paper.pdf"
    Then the answer is 200
    And the answer's "Content-Type" is "application/pdf"
    And the answer's "Cache-Control" is "public, max-age=31536000, immutable"

  Scenario: Uploading to a private tenant with public types stays closed
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true, "public_types": ["pdf"]}
      """
    And the form "paper" holding:
      | field | file     | content   |
      | file  | file.bin | a PDF     |
      | name  |          | other.pdf |
    When I send "POST" to "/sources/files" with the file "paper"
    Then the answer is 401
    And the bucket holds 0 objects

  Scenario: A cbor can't be stored as a public pdf
    Given the tenant "sources" is:
      """
      {"repository": "Sustenaut/business-plan", "origins": [], "files": {"types": ["pdf", "cbor", "json"], "max_bytes": 1000, "kept": true},
       "private": true, "editors": true, "public_types": ["pdf"]}
      """
    And requests carry the header "Authorization" set to "Bearer good"
    And the form "fake" holding:
      | field | file     | content    |
      | file  | file.bin | a CBOR map |
      | name  |          | fake.pdf   |
    When I send "POST" to "/sources/files" with the file "fake"
    Then the answer is 400
    And the bucket holds 0 objects
