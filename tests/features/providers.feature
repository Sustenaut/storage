@providers
Feature: The mirrors' indexes (src/storage.js): Terraform's provider network mirror, from the archives a tenant with "providers" keeps, and a simple repository index (PEP 503) of a tenant with "simple", with GitHub's OIDC issuer answered here

  Scenario: The terraform tenant is public, kept, never cleaned, serves the mirror protocol, and only storage's own main writes it
    Then the terraform tenant is public, kept, never cleaned, serves the mirror protocol, and only storage's own main writes it

  Scenario: index.json lists the versions mirrored, and <version>.json their archives with the zh: hash a lock pins
    Then index.json lists the versions mirrored, and <version>.json their archives with the zh: hash a lock pins

  Scenario: An archive is taken only named as a provider release names it, under its provider's address
    Then an archive is taken only named as a provider release names it, under its provider's address

  Scenario: A tenant without providers has no mirror routes
    Then a tenant without providers has no mirror routes

  Scenario: Versions are listed in release order, not as text
    Then versions are listed in release order, not as text

  Scenario: The pypi tenant is public, kept, never cleaned, serves a simple index, and only storage's own main writes it
    Then the pypi tenant is public, kept, never cleaned, serves a simple index, and only storage's own main writes it

  Scenario: A project's simple index links each of its files, with the sha256 a lock pins
    Then a project's simple index links each of its files, with the sha256 a lock pins

  Scenario: A package's file is taken only under its project's normalized name
    Then a package's file is taken only under its project's normalized name
