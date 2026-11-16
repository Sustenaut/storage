@inbox
Feature: Buffers: files in folders, listed and deleted, with tokens from a key made for the tests

  Scenario: A sender stores a file, and it can be read back, uncached
    Then a sender stores a file, and it can be read back, uncached

  Scenario: Sending a name again replaces the file, so a retry is safe
    Then sending a name again replaces the file, so a retry is safe

  Scenario: A file must be what its folder holds
    Then a file must be what its folder holds

  Scenario: A name outside the folders, or a way out of them, isn't a buffer's
    Then a name outside the folders, or a way out of them, isn't a buffer's

  Scenario: A file over the limit is refused
    Then a file over the limit is refused

  Scenario: Listing gives the oldest name first, a page at a time
    Then listing gives the oldest name first, a page at a time

  Scenario: A listing is only of a buffer's folders, with a sensible limit
    Then a listing is only of a buffer's folders, with a sensible limit

  Scenario: Only the delete list may delete, and writing isn't enough
    Then only the delete list may delete, and writing isn't enough

  Scenario: A person's token can't delete, and no token can't do anything
    Then a person's token can't delete, and no token can't do anything

  Scenario: One project's writers can't reach another's buffer
    Then one project's writers can't reach another's buffer

  Scenario: A tenant without a buffer, or a public one, has none of this
    Then a tenant without a buffer, or a public one, has none of this

  Scenario: Other methods on a buffer's file aren't allowed
    Then other methods on a buffer's file aren't allowed

  Scenario: Every buffer's deleter may also write and read it
    Then every buffer's deleter may also write and read it
