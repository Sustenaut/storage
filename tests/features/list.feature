@list
Feature: A private tenant's files, listed for its readers a page at a time, with what their uploads said of them, such as a subject

  Scenario: A reader lists the tenant's files with what their uploads said, and an upload may name its subject
    Then a reader lists the tenant's files with what their uploads said, and an upload may name its subject

  Scenario: A subject is cut to the label's length, and kept only when given
    Then a subject is cut to the label's length, and kept only when given

  Scenario: A listing comes a page at a time, and a prefix narrows it to an id or a name
    Then a listing comes a page at a time, and a prefix narrows it to an id or a name

  Scenario: Only a reader lists: no token, or a token that can't push, is refused
    Then only a reader lists: no token, or a token that can't push, is refused

  Scenario: A prefix outside f/, a bad one, or a bad limit is refused
    Then a prefix outside f/, a bad one, or a bad limit is refused

  Scenario: A public tenant is never listed, nor a private one's files without "files"
    Then a public tenant is never listed, nor a private one's files without "files"
