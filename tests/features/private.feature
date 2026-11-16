@private
Feature: Private tenants and OpenID Connect tokens (src/jwt.js), with GitHub's OIDC issuer and its key set answered here, from a key made for the tests

  Scenario: The publications tenant is private: business-plan's main writes it, pub-site, estimate and the review pod read it, kept
    Then the publications tenant is private: business-plan's main writes it, pub-site, estimate and the review pod read it, kept

  Scenario: A workflow's token writes a private file, and a reader gets it, never cached or shared
    Then a workflow's token writes a private file, and a reader gets it, never cached or shared

  Scenario: A private file is refused without a token of a principal on its lists, before anything is looked up
    Then a private file is refused without a token of a principal on its lists, before anything is looked up

  Scenario: Only the writers' principals, at their ref, write a private tenant; GitHub tokens never do
    Then only the writers' principals, at their ref, write a private tenant; GitHub tokens never do

  Scenario: A public tenant takes a workflow's token when its write list names it, and GitHub tokens as before
    Then a public tenant takes a workflow's token when its write list names it, and GitHub tokens as before

  Scenario: The wheels tenant is public, kept, never cleaned, and only storage's own main writes it
    Then the wheels tenant is public, kept, never cleaned, and only storage's own main writes it

  Scenario: A mirrored wheel is at the address its lock's sha256 names, for anyone, and a .whl must be a zip
    Then a mirrored wheel is at the address its lock's sha256 names, for anyone, and a .whl must be a zip

  Scenario: Tokens are refused unless RS256, from a trusted issuer, signed by its key, for this audience and in date
    Then tokens are refused unless RS256, from a trusted issuer, signed by its key, for this audience and in date

  Scenario: An audience list is taken when it includes this service
    Then an audience list is taken when it includes this service

  Scenario: The issuer's keys are fetched once, then again only when old or for a key they lack
    Then the issuer's keys are fetched once, then again only when old or for a key they lack

  Scenario: A principal matches a list entry by repository without case, and by ref when the entry names one
    Then a principal matches a list entry by repository without case, and by ref when the entry names one

  Scenario: GitHub tokens aren't taken for JWTs
    Then GitHub tokens aren't taken for JWTs

  Scenario: The clean-up leaves a private tenant alone
    Then the clean-up leaves a private tenant alone

  Scenario: A pod's service-account token names its namespace and account, against the pinned keys, without fetching
    Then a pod's service-account token names its namespace and account, against the pinned keys, without fetching

  Scenario: The opportunity tenant takes the opportunity app's pod token, and no other account's
    Then the opportunity tenant takes the opportunity app's pod token, and no other account's

  Scenario: The pinned k3s key set is the server's: an issuer and RSA signing keys
    Then the pinned k3s key set is the server's: an issuer and RSA signing keys
