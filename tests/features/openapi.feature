@openapi
Feature: openapi.json against the code: the spec is well formed, it names every route the header of src/storage.js lists and no other, and the code answers every route in it

  Scenario: The spec is OpenAPI 3.1, every reference resolves, and every operation is complete
    Then the spec is OpenAPI 3.1, every reference resolves, and every operation is complete

  Scenario: The spec has every route the header of src/storage.js lists, and no other
    Then the spec has every route the header of src/storage.js lists, and no other

  Scenario: The code answers <operation.method> <operation.path>
    Then the code answers <operation.method> <operation.path>

  Scenario: And a request for no route says so
    Then and a request for no route says so
