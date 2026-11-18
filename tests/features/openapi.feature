Feature: openapi.json against the code: the spec is well formed, it names every route the header of src/storage.js lists and no other, and the code answers every route in it

  Scenario Outline: The spec keeps a rule: <rule>
    When openapi.json is checked for the rule "<rule>"
    Then the result is empty

    Examples:
      | rule |
      | it is OpenAPI 3.1, with a title and a version |
      | every reference resolves |
      | every operation has a unique operationId of letters |
      | every operation has a summary |
      | every operation answers HTTP statuses, a success among them |
      | every error is an Error |
      | every operation says who may call it, by a scheme the spec has |
      | every name in a path is a required path parameter with an example, and nothing else is |

  Scenario: The spec has these operations
    When openapi.json's operations are listed
    Then the result is:
      """
      [
       "DELETE /{tenant}/batches/{name}",
       "DELETE /{tenant}/inbox/{path}",
       "DELETE /{tenant}/rejected/{path}",
       "GET /{tenant}/batches/{name}",
       "GET /{tenant}/f/{id}/{name}",
       "GET /{tenant}/head/{name}",
       "GET /{tenant}/head/{name}/log",
       "GET /{tenant}/inbox/{path}",
       "GET /{tenant}/list",
       "GET /{tenant}/p/{id}/{size}",
       "GET /{tenant}/rejected/{path}",
       "GET /{tenant}/simple/{project}/",
       "GET /{tenant}/{hostname}/{namespace}/{type}/{index}",
       "HEAD /{tenant}/batches/{name}",
       "HEAD /{tenant}/f/{id}/{name}",
       "HEAD /{tenant}/head/{name}",
       "HEAD /{tenant}/inbox/{path}",
       "HEAD /{tenant}/p/{id}/{size}",
       "HEAD /{tenant}/rejected/{path}",
       "HEAD /{tenant}/simple/{project}/",
       "HEAD /{tenant}/{hostname}/{namespace}/{type}/{index}",
       "POST /_clean",
       "POST /{tenant}/files",
       "POST /{tenant}/upload",
       "PUT /{tenant}/batches/{name}",
       "PUT /{tenant}/head/{name}",
       "PUT /{tenant}/inbox/{path}",
       "PUT /{tenant}/rejected/{path}"
      ]
      """

  Scenario: The header of src/storage.js lists the same routes, and no other
    When the routes the header of src/storage.js lists are read
    Then the result is:
      """
      [
       "DELETE /{tenant}/batches/{name}",
       "DELETE /{tenant}/inbox/{path}",
       "DELETE /{tenant}/rejected/{path}",
       "GET /{tenant}/batches/{name}",
       "GET /{tenant}/f/{id}/{name}",
       "GET /{tenant}/head/{name}",
       "GET /{tenant}/head/{name}/log",
       "GET /{tenant}/inbox/{path}",
       "GET /{tenant}/list",
       "GET /{tenant}/p/{id}/{size}",
       "GET /{tenant}/rejected/{path}",
       "GET /{tenant}/simple/{project}/",
       "GET /{tenant}/{hostname}/{namespace}/{type}/{index}",
       "HEAD /{tenant}/batches/{name}",
       "HEAD /{tenant}/f/{id}/{name}",
       "HEAD /{tenant}/head/{name}",
       "HEAD /{tenant}/inbox/{path}",
       "HEAD /{tenant}/p/{id}/{size}",
       "HEAD /{tenant}/rejected/{path}",
       "HEAD /{tenant}/simple/{project}/",
       "HEAD /{tenant}/{hostname}/{namespace}/{type}/{index}",
       "POST /_clean",
       "POST /{tenant}/files",
       "POST /{tenant}/upload",
       "PUT /{tenant}/batches/{name}",
       "PUT /{tenant}/head/{name}",
       "PUT /{tenant}/inbox/{path}",
       "PUT /{tenant}/rejected/{path}"
      ]
      """

  Scenario Outline: The spec's example of <method> <path>
    When the example of "<method> <path>" is read from openapi.json
    Then the result is "<example>"

    Examples:
      | method | path                                            | example                                                                            | status |
      | GET    | /{tenant}/p/{id}/{size}                         | /all/p/0123456789abcdef/960.webp                                                   | 404    |
      | HEAD   | /{tenant}/p/{id}/{size}                         | /all/p/0123456789abcdef/960.webp                                                   | 404    |
      | POST   | /{tenant}/upload                                | /all/upload                                                                        | 500    |
      | GET    | /{tenant}/f/{id}/{name}                         | /all/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/report.pdf | 404    |
      | HEAD   | /{tenant}/f/{id}/{name}                         | /all/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/report.pdf | 404    |
      | POST   | /{tenant}/files                                 | /all/files                                                                         | 500    |
      | GET    | /{tenant}/head/{name}                           | /all/head/board                                                                    | 404    |
      | PUT    | /{tenant}/head/{name}                           | /all/head/board                                                                    | 412    |
      | HEAD   | /{tenant}/head/{name}                           | /all/head/board                                                                    | 404    |
      | GET    | /{tenant}/head/{name}/log                       | /all/head/board/log                                                                | 404    |
      | GET    | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 404    |
      | PUT    | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 400    |
      | DELETE | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 401    |
      | HEAD   | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 404    |
      | GET    | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 404    |
      | PUT    | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 400    |
      | DELETE | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 401    |
      | HEAD   | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 404    |
      | GET    | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 404    |
      | PUT    | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 400    |
      | DELETE | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 401    |
      | HEAD   | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 404    |
      | GET    | /{tenant}/list                                  | /all/list?prefix=f%2F                                                              | 200    |
      | GET    | /{tenant}/{hostname}/{namespace}/{type}/{index} | /all/registry.terraform.io/hashicorp/google/index.json                             | 200    |
      | HEAD   | /{tenant}/{hostname}/{namespace}/{type}/{index} | /all/registry.terraform.io/hashicorp/google/index.json                             | 200    |
      | GET    | /{tenant}/simple/{project}/                     | /all/simple/pytest/                                                                | 404    |
      | HEAD   | /{tenant}/simple/{project}/                     | /all/simple/pytest/                                                                | 404    |
      | POST   | /_clean                                         | /_clean                                                                            | 200    |

  # A tenant with everything, a GitHub token that may push to it, and an empty bucket:
  # a request that reaches its route gets past the route's own checks or fails them,
  # but never gets "no such route".

  Scenario Outline: The code answers <method> <path>
    Given the tenant "all" is:
      """
      {"private": true, "editors": true, "repository": "o/all", "files": {"types": ["pdf"]}, "heads": true, "inbox": true,
       "providers": true, "simple": true, "read": [], "write": [], "delete": []}
      """
    And GitHub lets the token push to "o/all"
    And GitHub knows the token as "editor"
    And requests carry the header "Authorization" set to "Bearer gho_editor"
    When I send "<method>" to "<example>"
    Then the answer is <status>
    And the answer does not include "no such route"

    Examples:
      | method | path                                            | example                                                                            | status |
      | GET    | /{tenant}/p/{id}/{size}                         | /all/p/0123456789abcdef/960.webp                                                   | 404    |
      | HEAD   | /{tenant}/p/{id}/{size}                         | /all/p/0123456789abcdef/960.webp                                                   | 404    |
      | POST   | /{tenant}/upload                                | /all/upload                                                                        | 500    |
      | GET    | /{tenant}/f/{id}/{name}                         | /all/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/report.pdf | 404    |
      | HEAD   | /{tenant}/f/{id}/{name}                         | /all/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/report.pdf | 404    |
      | POST   | /{tenant}/files                                 | /all/files                                                                         | 500    |
      | GET    | /{tenant}/head/{name}                           | /all/head/board                                                                    | 404    |
      | PUT    | /{tenant}/head/{name}                           | /all/head/board                                                                    | 412    |
      | HEAD   | /{tenant}/head/{name}                           | /all/head/board                                                                    | 404    |
      | GET    | /{tenant}/head/{name}/log                       | /all/head/board/log                                                                | 404    |
      | GET    | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 404    |
      | PUT    | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 400    |
      | DELETE | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 401    |
      | HEAD   | /{tenant}/inbox/{path}                          | /all/inbox/calls/2026-11-06/080200-web-0123456789abcdef.avro                       | 404    |
      | GET    | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 404    |
      | PUT    | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 400    |
      | DELETE | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 401    |
      | HEAD   | /{tenant}/rejected/{path}                       | /all/rejected/calls/2026-11-06/080200-web-0123456789abcdef.avro                    | 404    |
      | GET    | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 404    |
      | PUT    | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 400    |
      | DELETE | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 401    |
      | HEAD   | /{tenant}/batches/{name}                        | /all/batches/job-1.json                                                            | 404    |
      | GET    | /{tenant}/list                                  | /all/list?prefix=f%2F                                                              | 200    |
      | GET    | /{tenant}/{hostname}/{namespace}/{type}/{index} | /all/registry.terraform.io/hashicorp/google/index.json                             | 200    |
      | HEAD   | /{tenant}/{hostname}/{namespace}/{type}/{index} | /all/registry.terraform.io/hashicorp/google/index.json                             | 200    |
      | GET    | /{tenant}/simple/{project}/                     | /all/simple/pytest/                                                                | 404    |
      | HEAD   | /{tenant}/simple/{project}/                     | /all/simple/pytest/                                                                | 404    |
      | POST   | /_clean                                         | /_clean                                                                            | 200    |

  Scenario Outline: A request for no route says so: <method> <path>
    Given the tenant "all" is:
      """
      {"private": true, "editors": true, "repository": "o/all", "files": {"types": ["pdf"]}, "heads": true, "inbox": true,
       "providers": true, "simple": true, "read": [], "write": [], "delete": []}
      """
    And GitHub lets the token push to "o/all"
    And GitHub knows the token as "editor"
    And requests carry the header "Authorization" set to "Bearer gho_editor"
    When I send "<method>" to "<path>"
    Then the answer includes '"error":"no such route'

    Examples:
      | method | path                                                                         |
      | GET    | /all/nothing                                                                 |
      | POST   | /all/p/0123456789abcdef/960.jpg                                              |
      | PUT    | /all/f/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.pdf |
      | PATCH  | /all/head/board                                                              |
      | POST   | /all/inbox/a.avro                                                            |
      | DELETE | /all/files                                                                   |
