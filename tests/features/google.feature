@google
Feature: Google identity tokens, as a Cloud Run service's metadata server gives them, with Google's key set answered here, from a key made for the tests

  Scenario: A service account's identity token names its verified address
    Then a service account's identity token names its verified address

  Scenario: A Google token for another audience, out of date, or not signed by Google is refused
    Then a Google token for another audience, out of date, or not signed by Google is refused

  Scenario: Only a verified service account's address is a principal
    Then only a verified service account's address is a principal

  Scenario: A tenant's list names Google accounts exactly
    Then a tenant's list names Google accounts exactly
