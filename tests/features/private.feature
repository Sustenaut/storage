Feature: Private tenants and workflows' tokens: OpenID Connect tokens (src/jwt.js) on a tenant's read and write lists
  The storage service (src/storage.js) with an R2 bucket in memory, Cloudflare's
  Cache API kept in memory, GitHub a fake service, and GitHub's OIDC issuer a
  fake service publishing a key made for the tests.

  Background:
    Given a scratch directory
    And the time is "2026-11-01T00:00:00Z"
    And the "GitHub's OIDC issuer" service publishes its test keys
    And the tenant "publications" as tenants.json has it, but with:
      """
      {"editors": false}
      """
    And the tenant "photos" is:
      """
      {"repository": "schryer/visit-ee", "origins": [], "write": ["github:schryer/visit-ee@refs/heads/main"], "files": {"types": ["pdf"]}}
      """
    And the tenant "plain" is:
      """
      {"repository": "schryer/visit-ee", "origins": [], "files": {"types": ["pdf"]}}
      """
    And the tenant "wheels" as tenants.json has it
    And GitHub lets the token push to "schryer/visit-ee"
    And GitHub knows the token as "schryer"

  Scenario: A workflow's token writes a private file, kept, recorded as by its principal
    Given requests carry a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And the form "publication" holding:
      | field | file                          | content |
      | file  | publication-0-objects.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    When I send "POST" to "/publications/files" with the file "publication"
    Then the answer is 200
    And the answer includes '"url":"/publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/publication-0-objects.tar.gz"'
    And the answer includes '"kept":true'
    And the bucket's "publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/publication-0-objects.tar.gz" has the metadata "by" set to "github:Sustenaut/business-plan@refs/heads/main"

  Scenario Outline: A reader gets a private file, never cached or shared: <method>
    Given the bucket already holds:
      | key                                                                                             | content |
      | publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/publication-0-objects.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    And requests carry a GitHub Actions token for "Sustenaut/pub-site" at "refs/pull/3/merge"
    When I send "<method>" to "/publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/publication-0-objects.tar.gz"
    Then the answer is 200
    And the answer's "Content-Type" is "application/gzip"
    And the answer's "Cache-Control" is "private, no-store"
    And the answer has no "Access-Control-Allow-Origin"
    And the answer's "Vary" is "Authorization, Origin"
    And the answer's <body>
    And the Cache API was never asked

    Examples:
      | method | body                                                    |
      | GET    | bytes are "1f 8b 08 00 00 00 00 00 00 03 01 02 03"       |
      | HEAD   | body is empty                                           |

  Scenario: A writer may read what it wrote
    Given the bucket already holds:
      | key                                                                                             | content |
      | publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/publication-0-objects.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    And requests carry a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    When I GET "/publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/publication-0-objects.tar.gz"
    Then the answer is 200
    And the Cache API was never asked

  Scenario: A private file is refused without a token
    Given the bucket already holds:
      | key                                     | content |
      | publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    When I GET "/publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz"
    Then the answer is 401

  Scenario: A private file is refused with a GitHub token: those aren't taken
    Given the bucket already holds:
      | key                                     | content |
      | publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    And requests carry the header "Authorization" set to "Bearer ghp_aPersonalToken"
    When I GET "/publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz"
    Then the answer is 401

  Scenario Outline: A private file is refused to a principal on none of its lists: <repository>, a name matched whole
    Given the bucket already holds:
      | key                                     | content |
      | publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    And requests carry a GitHub Actions token for "<repository>" at "refs/heads/main"
    When I GET "/publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz"
    Then the answer is 403
    And the answer includes "may not read here"

    Examples:
      | repository              |
      | schryer/visit-ee        |
      | Sustenaut/pub-site-fork |

  Scenario: No token learns nothing, even of what isn't there
    When I GET "/publications/f/0000000000000000000000000000000000000000000000000000000000000000/x.tar.gz"
    Then the answer is 401

  Scenario: A reader learns what isn't there
    Given requests carry a GitHub Actions token for "Sustenaut/pub-site" at "refs/heads/main"
    When I GET "/publications/f/0000000000000000000000000000000000000000000000000000000000000000/x.tar.gz"
    Then the answer is 404

  Scenario Outline: Only the writers' principals, at their ref, write a private tenant: <repository> at <ref>
    Given requests carry a GitHub Actions token for "<repository>" at "<ref>"
    And the form "publication" holding:
      | field | file                          | content |
      | file  | publication-0-objects.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    When I send "POST" to "/publications/files" with the file "publication"
    Then the answer is 403
    And the bucket holds 0 objects

    Examples:
      | repository              | ref                |
      | Sustenaut/pub-site      | refs/heads/main    |
      | Sustenaut/business-plan | refs/heads/feature |
      | Sustenaut/business-plan | refs/pull/9/merge  |

  Scenario Outline: GitHub tokens never write a private tenant: <token>
    Given requests carry the header "Authorization" set to "Bearer <token>"
    And the form "publication" holding:
      | field | file                          | content |
      | file  | publication-0-objects.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 |
    When I send "POST" to "/publications/files" with the file "publication"
    Then the answer is 401
    And the bucket holds 0 objects

    Examples:
      | token   |
      | good    |
      | ghs_app |

  Scenario Outline: A private tenant's writer still writes only its types: <file> holding <content>
    Given requests carry a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And the form "file" holding:
      | field | file   | content   |
      | file  | <file> | <content> |
    When I send "POST" to "/publications/files" with the file "file"
    Then the answer is <status>
    And the answer includes "<says>"
    And the bucket holds 0 objects

    Examples:
      | file     | content                   | status | says                      |
      | p.pdf    | the text %PDF-1.7 a paper | 415    | not .pdf                  |
      | p.tar.gz | the text %PDF-1.7 a paper | 400    | p.tar.gz is not a .gz file |

  Scenario: A public tenant takes a workflow's token when its write list names it
    Given requests carry a GitHub Actions token for "schryer/visit-ee" at "refs/heads/main"
    And the form "paper" holding:
      | field | file  | content                    |
      | file  | a.pdf | the text %PDF-1.7 a paper |
    When I send "POST" to "/photos/files" with the file "paper"
    Then the answer is 200

  Scenario: A public tenant takes a workflow's token only at the ref its write list names
    Given requests carry a GitHub Actions token for "schryer/visit-ee" at "refs/heads/x"
    And the form "paper" holding:
      | field | file  | content                    |
      | file  | a.pdf | the text %PDF-1.7 a paper |
    When I send "POST" to "/photos/files" with the file "paper"
    Then the answer is 403

  Scenario: A public tenant without a write list takes no workflow's token
    Given requests carry a GitHub Actions token for "schryer/visit-ee" at "refs/heads/main"
    And the form "paper" holding:
      | field | file  | content                    |
      | file  | a.pdf | the text %PDF-1.7 a paper |
    When I send "POST" to "/plain/files" with the file "paper"
    Then the answer is 403

  Scenario: A public tenant takes its editors' GitHub tokens as before
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "paper" holding:
      | field | file  | content                    |
      | file  | a.pdf | the text %PDF-1.7 a paper |
    When I send "POST" to "/plain/files" with the file "paper"
    Then the answer is 200

  Scenario: A public tenant's files need no token, and are cached and shared
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "b" holding:
      | field | file  | content                    |
      | file  | b.pdf | the text %PDF-1.7 a paper |
    And I have sent "POST" to "/photos/files" with the file "b", answered 200
    And requests carry the header "Authorization" set to "Bearer "
    When I GET "/photos/f/be745a9e5b9d2be07ab3bf55149ef20694c2733d1a4eae8c8c4d2109d977f1ff/b.pdf"
    Then the answer is 200
    And the answer's "Access-Control-Allow-Origin" is "*"
    And the answer's "Cache-Control" is "public, max-age=31536000, immutable"

  Scenario: A mirrored wheel is stored at the address its lock's sha256 names, kept
    Given requests carry a GitHub Actions token for "Sustenaut/storage" at "refs/heads/main"
    And the form "wheel" holding:
      | field | file                             | content                          |
      | file  | pubrules-0.31.3-py3-none-any.whl | the bytes 50 4b 03 04 01 02 03 04 |
    When I send "POST" to "/wheels/files" with the file "wheel"
    Then the answer is 200
    And the answer includes '"url":"/wheels/f/5702eec1ac8168696925fa05d9c3c0d9cc46153618daebfdad8a551907968dea/pubrules-0.31.3-py3-none-any.whl"'
    And the answer includes '"kept":true'

  Scenario: A mirrored wheel is served to anyone, as a zip
    Given the bucket already holds:
      | key                                                   | content                           |
      | wheels/f/5702eec1ac8168696925fa05d9c3c0d9cc46153618daebfdad8a551907968dea/pubrules-0.31.3-py3-none-any.whl | the bytes 50 4b 03 04 01 02 03 04 |
    When I GET "/wheels/f/5702eec1ac8168696925fa05d9c3c0d9cc46153618daebfdad8a551907968dea/pubrules-0.31.3-py3-none-any.whl"
    Then the answer is 200
    And the answer's "Content-Type" is "application/zip"
    And the answer's bytes are "50 4b 03 04 01 02 03 04"

  Scenario Outline: Only storage's own main writes a wheel: <repository> at <ref>
    Given requests carry a GitHub Actions token for "<repository>" at "<ref>"
    And the form "wheel" holding:
      | field | file                             | content                           |
      | file  | pubrules-0.31.3-py3-none-any.whl | the bytes 50 4b 03 04 01 02 03 04 |
    When I send "POST" to "/wheels/files" with the file "wheel"
    Then the answer is 403
    And the bucket holds 0 objects

    Examples:
      | repository         | ref             |
      | Sustenaut/storage  | refs/heads/x    |
      | Sustenaut/pubrules | refs/heads/main |

  Scenario: No GitHub token writes a wheel
    Given requests carry the header "Authorization" set to "Bearer good"
    And the form "wheel" holding:
      | field | file                             | content                           |
      | file  | pubrules-0.31.3-py3-none-any.whl | the bytes 50 4b 03 04 01 02 03 04 |
    When I send "POST" to "/wheels/files" with the file "wheel"
    Then the answer is 401

  Scenario Outline: A wheel must be a zip, and nothing else is a wheel: <file>
    Given requests carry a GitHub Actions token for "Sustenaut/storage" at "refs/heads/main"
    And the form "wheel" holding:
      | field | file   | content                   |
      | file  | <file> | the text %PDF-1.7 a paper |
    When I send "POST" to "/wheels/files" with the file "wheel"
    Then the answer is <status>

    Examples:
      | file                             | status |
      | pubrules-0.31.3-py3-none-any.whl | 400    |
      | a.pdf                            | 415    |

  Scenario: The clean-up leaves a private tenant alone
    Given the tenant "publications" as tenants.json has it, but with:
      """
      {"editors": false, "in_use": "https://example/in-use.json"}
      """
    And the bucket already holds:
      | key                                     | content | kept  | uploaded                 |
      | publications/f/927d8566f4887a56a157f225e00e7126a339b8386ae78fca28641070bc1a468c/p.tar.gz | the bytes 1f 8b 08 00 00 00 00 00 00 03 01 02 03 | false | 2025-10-27T00:00:00.000Z |
    When the clean-up runs at "2027-11-01T00:00:00Z"
    Then the result's "publications" is '{"skipped": "private: nothing is cleaned"}'
    And the bucket holds 1 objects
