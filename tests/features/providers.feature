Feature: The mirrors' indexes: Terraform's provider network mirror of a tenant with "providers", and a simple repository index (PEP 503) of a tenant with "simple"
  The storage service (src/storage.js) with tenants.json's terraform, wheels and
  pypi tenants, an R2 bucket in memory that lists two objects a page (so an index
  reads every page), and GitHub's OIDC issuer a fake service publishing a key
  made for the tests. The archives' contents and their SHA-256:

    50 4b 03 04 01  53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c
    50 4b 03 04 02  bafefe650939faec81979339bfbfebd5befa13ce6d2d3091b6e8a23a136785c1
    50 4b 03 04 03  14821fb431fd6d011e8331cf0542362db03e6ed6b62dde8b8ba02c6df6f1785d
    50 4b 03 04 04  68493be2d32af2d793cba5c45268b3a7375c4a25c0668d479aaa31c24a31bedb
    1f 8b 08 00     fd72d30440b0bae1b1c6db6c8ad807f238ef3ca613aa7e8d5329e1e8ddf7da72

  Background:
    Given a scratch directory
    And the "GitHub's OIDC issuer" service publishes its test keys
    And the tenant "terraform" as tenants.json has it
    And the tenant "wheels" as tenants.json has it
    And the tenant "pypi" as tenants.json has it
    And the bucket lists 2 objects a page
    And requests carry a GitHub Actions token for "Sustenaut/storage" at "refs/heads/main"

  Scenario: A provider's archive is kept under its provider's address
    Given the form "archive" holding:
      | field   | file                                            | content                  |
      | file    | terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 |
      | subject |                                                 | registry.terraform.io/hashicorp/google |
    When I send "POST" to "/terraform/files" with the file "archive"
    Then the answer is 200
    And the bucket's "terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip" has the metadata "subject" set to "registry.terraform.io/hashicorp/google"

  Scenario: index.json lists the versions mirrored of its provider alone, for five minutes
    Given the bucket already holds:
      | key                                                                                                   | content                  | subject |
      | terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/google |
      | terraform/f/bafefe650939faec81979339bfbfebd5befa13ce6d2d3091b6e8a23a136785c1/terraform-provider-google_7.0.0_darwin_arm64.zip | the bytes 50 4b 03 04 02 | registry.terraform.io/hashicorp/google |
      | terraform/f/14821fb431fd6d011e8331cf0542362db03e6ed6b62dde8b8ba02c6df6f1785d/terraform-provider-google_6.9.0_linux_amd64.zip | the bytes 50 4b 03 04 03 | registry.terraform.io/hashicorp/google |
      | terraform/f/68493be2d32af2d793cba5c45268b3a7375c4a25c0668d479aaa31c24a31bedb/terraform-provider-tls_4.0.0_linux_amd64.zip | the bytes 50 4b 03 04 04 | registry.terraform.io/hashicorp/tls |
    When I GET "/terraform/registry.terraform.io/hashicorp/google/index.json"
    Then the answer is 200
    And the answer's "Cache-Control" is "public, max-age=300"
    And the answer is the JSON:
      """
      {"versions": {"6.9.0": {}, "7.0.0": {}}}
      """

  Scenario: A version's .json lists the version's archives, each with the zh: hash a lock pins
    Given the bucket already holds:
      | key                                                                                                   | content                  | subject |
      | terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/google |
      | terraform/f/bafefe650939faec81979339bfbfebd5befa13ce6d2d3091b6e8a23a136785c1/terraform-provider-google_7.0.0_darwin_arm64.zip | the bytes 50 4b 03 04 02 | registry.terraform.io/hashicorp/google |
      | terraform/f/14821fb431fd6d011e8331cf0542362db03e6ed6b62dde8b8ba02c6df6f1785d/terraform-provider-google_6.9.0_linux_amd64.zip | the bytes 50 4b 03 04 03 | registry.terraform.io/hashicorp/google |
    When I GET "/terraform/registry.terraform.io/hashicorp/google/7.0.0.json"
    Then the answer is 200
    And the answer is the JSON:
      """
      {"archives": {
        "linux_amd64": {"url": "https://storage.example/terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip", "hashes": ["zh:53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c"]},
        "darwin_arm64": {"url": "https://storage.example/terraform/f/bafefe650939faec81979339bfbfebd5befa13ce6d2d3091b6e8a23a136785c1/terraform-provider-google_7.0.0_darwin_arm64.zip", "hashes": ["zh:bafefe650939faec81979339bfbfebd5befa13ce6d2d3091b6e8a23a136785c1"]}
      }}
      """

  Scenario: An archive is where its version says
    Given the bucket already holds:
      | key                                                                                                   | content                  | subject |
      | terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/google |
    When I GET "/terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip"
    Then the answer is 200
    And the answer's bytes are "50 4b 03 04 01"

  Scenario: A version not mirrored is not found
    Given the bucket already holds:
      | key                                                                                                   | content                  | subject |
      | terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/google |
    When I GET "/terraform/registry.terraform.io/hashicorp/google/5.0.0.json"
    Then the answer is 404

  Scenario: A provider not mirrored has no versions
    When I GET "/terraform/registry.terraform.io/hashicorp/nothing/index.json"
    Then the answer is the JSON:
      """
      {"versions": {}}
      """

  Scenario: HEAD asks for an index too
    When I send "HEAD" to "/terraform/registry.terraform.io/hashicorp/google/index.json"
    Then the answer is 200

  Scenario Outline: An archive is taken only named as a provider release names it, under its provider's address: <why>
    Given the form "archive" holding:
      | field   | file   | content   |
      | file    | <file> | <content> |
      | subject |        | <subject> |
    When I send "POST" to "/terraform/files" with the file "archive"
    Then the answer is 400
    And the bucket holds 0 objects

    Examples:
      | why              | file                                            | content                  | subject                             |
      | not so named     | google.zip                                      | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/google |
      | no hostname      | terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | hashicorp/google                    |
      | another provider | terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/tls |
      | not a zip        | terraform-provider-google_7.0.0_linux_amd64.zip | the text not a zip       | registry.terraform.io/hashicorp/google |

  Scenario: An archive without a subject is refused
    Given the form "archive" holding:
      | field | file                                            | content                  |
      | file  | terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 |
    When I send "POST" to "/terraform/files" with the file "archive"
    Then the answer is 400
    And the answer includes "the subject is the provider's address"
    And the bucket holds 0 objects

  Scenario: Only storage's own main writes an archive
    Given requests carry a GitHub Actions token for "Sustenaut/business-plan" at "refs/heads/main"
    And the form "archive" holding:
      | field   | file                                            | content                  |
      | file    | terraform-provider-google_7.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 |
      | subject |                                                 | registry.terraform.io/hashicorp/google |
    When I send "POST" to "/terraform/files" with the file "archive"
    Then the answer is 403
    And the bucket holds 0 objects

  Scenario: A tenant without providers has no mirror routes
    When I GET "/wheels/registry.terraform.io/hashicorp/google/index.json"
    Then the answer is 404

  Scenario: Versions are put in release order, not as text
    When the versions '["10.0.0", "9.1.0", "9.0.10", "9.0.9", "10.0.0-beta1", "10.0.0-alpha2"]' are put in release order
    Then the result is:
      """
      ["9.0.9", "9.0.10", "9.1.0", "10.0.0-alpha2", "10.0.0-beta1", "10.0.0"]
      """

  Scenario: A version is in the same place as itself
    When "1.2.3" and "1.2.3" are compared in release order
    Then the result is "0"

  Scenario: index.json lists the versions in release order
    Given the bucket already holds:
      | key                                                                                                | content                  | subject |
      | terraform/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/terraform-provider-tls_10.0.0_linux_amd64.zip | the bytes 50 4b 03 04 01 | registry.terraform.io/hashicorp/tls |
      | terraform/f/bafefe650939faec81979339bfbfebd5befa13ce6d2d3091b6e8a23a136785c1/terraform-provider-tls_9.0.0_linux_amd64.zip | the bytes 50 4b 03 04 02 | registry.terraform.io/hashicorp/tls |
    When I GET "/terraform/registry.terraform.io/hashicorp/tls/index.json"
    Then the answer includes '{"versions":{"9.0.0":{},"10.0.0":{}}}'

  Scenario Outline: A project's file is kept under its normalized name: <file>
    Given the form "package" holding:
      | field   | file   | content   |
      | file    | <file> | <content> |
      | subject |        | <subject> |
    When I send "POST" to "/pypi/files" with the file "package"
    Then the answer is <status>

    Examples:
      | file                                              | content                  | subject    | status |
      | PyYAML-6.0.3-cp314-cp314-manylinux_2_17_x86_64.whl | the bytes 50 4b 03 04 01 | pyyaml     | 200    |
      | pyyaml-6.0.3.tar.gz                               | the bytes 50 4b 03 04 02 | pyyaml     | 400    |
      | pyyaml-6.0.3.tar.gz                               | the bytes 1f 8b 08 00    | pyyaml     | 200    |
      | pytest_bdd-8.1.0-py3-none-any.whl                 | the bytes 50 4b 03 04 03 | pytest-bdd | 200    |

  Scenario: A project's simple index links each of its files, with the sha256 a lock pins, and no other project's
    Given the bucket already holds:
      | key                                                                                                     | content                  | subject    |
      | pypi/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/PyYAML-6.0.3-cp314-cp314-manylinux_2_17_x86_64.whl | the bytes 50 4b 03 04 01 | pyyaml     |
      | pypi/f/fd72d30440b0bae1b1c6db6c8ad807f238ef3ca613aa7e8d5329e1e8ddf7da72/pyyaml-6.0.3.tar.gz | the bytes 1f 8b 08 00    | pyyaml     |
      | pypi/f/14821fb431fd6d011e8331cf0542362db03e6ed6b62dde8b8ba02c6df6f1785d/pytest_bdd-8.1.0-py3-none-any.whl | the bytes 50 4b 03 04 03 | pytest-bdd |
    When I GET "/pypi/simple/PyYAML/"
    Then the answer is 200
    And the answer's "Content-Type" is "text/html; charset=utf-8"
    And the answer includes '<a href="https://storage.example/pypi/f/53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c/PyYAML-6.0.3-cp314-cp314-manylinux_2_17_x86_64.whl#sha256=53f1fcd90b4cd1bd14afd136c9b18b8a1cf72c70387704d423a6eed37746257c">'
    And the answer includes '#sha256=fd72d30440b0bae1b1c6db6c8ad807f238ef3ca613aa7e8d5329e1e8ddf7da72">pyyaml-6.0.3.tar.gz</a>'
    And the answer does not include "pytest_bdd"

  Scenario: A project's name is normalized
    Given the bucket already holds:
      | key                                                                                                     | content                  | subject    |
      | pypi/f/14821fb431fd6d011e8331cf0542362db03e6ed6b62dde8b8ba02c6df6f1785d/pytest_bdd-8.1.0-py3-none-any.whl | the bytes 50 4b 03 04 03 | pytest-bdd |
    When I GET "/pypi/simple/pytest_bdd/"
    Then the answer includes "pytest_bdd-8.1.0-py3-none-any.whl"

  Scenario: A project not mirrored has no index
    When I GET "/pypi/simple/nothing/"
    Then the answer is 404

  Scenario: HEAD asks for a simple index too
    Given the bucket already holds:
      | key                                                                                                     | content                  | subject    |
      | pypi/f/fd72d30440b0bae1b1c6db6c8ad807f238ef3ca613aa7e8d5329e1e8ddf7da72/pyyaml-6.0.3.tar.gz | the bytes 1f 8b 08 00    | pyyaml     |
    When I send "HEAD" to "/pypi/simple/pyyaml/"
    Then the answer is 200

  Scenario: Only a tenant with simple has an index
    When I GET "/terraform/simple/pyyaml/"
    Then the answer is 404

  Scenario Outline: A package's file is taken only under its project's normalized name: <why>
    Given the form "package" holding:
      | field   | file   | content                  |
      | file    | <file> | the bytes 50 4b 03 04 01 |
      | subject |        | <subject>                |
    When I send "POST" to "/pypi/files" with the file "package"
    Then the answer is 400
    And the bucket holds 0 objects

    Examples:
      | why                 | file                              | subject |
      | not normalized      | pytest-9.0.3-py3-none-any.whl     | PyTest  |
      | another project     | pytest-9.0.3-py3-none-any.whl     | pyyaml  |
      | a name matched whole | pytest_bdd-8.1.0-py3-none-any.whl | pytest  |

  Scenario: A package's file without a subject is refused
    Given the form "package" holding:
      | field | file                          | content                  |
      | file  | pytest-9.0.3-py3-none-any.whl | the bytes 50 4b 03 04 01 |
    When I send "POST" to "/pypi/files" with the file "package"
    Then the answer is 400
    And the bucket holds 0 objects
