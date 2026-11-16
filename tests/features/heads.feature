@heads
Feature: Named heads, with the bucket's conditional writes as R2 does them and tokens from a key made for the tests

  Scenario: A head serves the file it points at, with its hash as the ETag, uncached
    Then a head serves the file it points at, with its hash as the ETag, uncached

  Scenario: HEAD gives the hash without the file
    Then HEAD gives the hash without the file

  Scenario: A head that has never moved is not found, and takes only If-None-Match: *
    Then a head that has never moved is not found, and takes only If-None-Match: *

  Scenario: Moving needs the current hash, and answers 412 otherwise
    Then moving needs the current hash, and answers 412 otherwise

  Scenario: If-Match takes a bare or weak hash as well as a quoted one
    Then If-Match takes a bare or weak hash as well as a quoted one

  Scenario: Of two moves from the same place, only one wins
    Then of two moves from the same place, only one wins

  Scenario: Two first moves at once: only one wins
    Then two first moves at once: only one wins

  Scenario: The log lists every place, newest first, with time and principal
    Then the log lists every place, newest first, with time and principal

  Scenario: A move that fails loses nothing and adds nothing false to the log
    Then a move that fails loses nothing and adds nothing false to the log

  Scenario: Moving to where it already points changes nothing
    Then moving to where it already points changes nothing

  Scenario: A head can only point at a stored file
    Then a head can only point at a stored file

  Scenario: Each name is its own head
    Then each name is its own head

  Scenario: Only the write list moves a head, and only readers read one
    Then only the write list moves a head, and only readers read one

  Scenario: A tenant without heads, or a public one, has none
    Then a tenant without heads, or a public one, has none

  Scenario: Each release tenant is read by its own deployment alone
    Then each release tenant is read by its own deployment alone

  Scenario: One deployment's token can't read the other's tenant
    Then one deployment's token can't read the other's tenant

  Scenario: The plane tenant is read and written by each plane repository's main and the convergence engine alone
    Then the plane tenant is read and written by each plane repository's main and the convergence engine alone

  Scenario: One plane repository's main writes a head another reads; others can't
    Then one plane repository's main writes a head another reads; others can't
