@storage
Feature: The storage service (src/storage.js), with an R2 bucket in memory and GitHub answered here

  Scenario: An editor's upload is stored and named by its content
    Then an editor's upload is stored and named by its content

  Scenario: Only someone who may push to the repository can upload
    Then only someone who may push to the repository can upload

  Scenario: An upload must be photos of allowed sizes
    Then an upload must be photos of allowed sizes

  Scenario: The clean-up deletes old photos no place uses, and nothing else
    Then the clean-up deletes old photos no place uses, and nothing else

  Scenario: A JPEG's size comes from its frame header
    Then a JPEG's size comes from its frame header

  Scenario: The clean-up runs once a day however often it is called, and other sites' paths are unknown
    Then the clean-up runs once a day however often it is called, and other sites' paths are unknown

  Scenario: A file is stored under its content's SHA-256 and served with its type, for good
    Then a file is stored under its content's SHA-256 and served with its type, for good

  Scenario: Files must be of a type the tenant allows, look like it, and fit
    Then files must be of a type the tenant allows, look like it, and fit

  Scenario: Only someone who may push to the tenant's repository can upload a file
    Then only someone who may push to the tenant's repository can upload a file

  Scenario: A GitHub App installation token uploads when its installation can write to the repository
    Then a GitHub App installation token uploads when its installation can write to the repository

  Scenario: Kept files are never cleaned, others are cleaned like photos, and only when the list names files
    Then kept files are never cleaned, others are cleaned like photos, and only when the list names files

  Scenario: A kept file stays kept when the same file is uploaded again
    Then a kept file stays kept when the same file is uploaded again

  Scenario: The opportunity tenant takes the files the opportunity site needs
    Then the opportunity tenant takes the files the opportunity site needs

  Scenario: A sources tenant keeps papers, publet objects and their index, all kept
    Then a sources tenant keeps papers, publet objects and their index, all kept

  Scenario: A cbor file must be a CBOR map and a json file must parse
    Then a cbor file must be a CBOR map and a json file must parse

  Scenario: A tenant without an in_use list has nothing cleaned
    Then a tenant without an in_use list has nothing cleaned

  Scenario: A private tenant with editors takes a GitHub token that may push, for reading and writing, and is never public
    Then a private tenant with editors takes a GitHub token that may push, for reading and writing, and is never public

  Scenario: A private tenant's public_types are open to anyone, and nothing else in it is
    Then a private tenant's public_types are open to anyone, and nothing else in it is

  Scenario: The pdc tenant is public, and only pub-site's main writes it: kept signed objects and their reading data
    Then the pdc tenant is public, and only pub-site's main writes it: kept signed objects and their reading data

  Scenario: The facts tenant is private: business-plan's editors upload, its main reads, kept, signed objects only
    Then the facts tenant is private: business-plan's editors upload, its main reads, kept, signed objects only

  Scenario: The sources tenant is private: business-plan's main and the review pod read it, its editors still upload and move its heads, kept and never cleaned
    Then the sources tenant is private: business-plan's main and the review pod read it, its editors still upload and move its heads, kept and never cleaned

  Scenario: An avro file must start as Avro does
    Then an avro file must start as Avro does

  Scenario: GitHub's yes is kept a minute, so more uploads with the same token don't ask again
    Then GitHub's yes is kept a minute, so more uploads with the same token don't ask again

  Scenario: A kept yes expires after a minute, and then a revoked permission is refused
    Then a kept yes expires after a minute, and then a revoked permission is refused

  Scenario: A no, or an error, is never kept
    Then a no, or an error, is never kept

  Scenario: The cache is keyed by a hash of the token and repository, never the token
    Then the cache is keyed by a hash of the token and repository, never the token

  Scenario: The cache holds at most a thousand yeses, dropping the oldest
    Then the cache holds at most a thousand yeses, dropping the oldest

  Scenario: Every call to GitHub has a timeout, and GitHub not answering is a 503, not a refusal
    Then every call to GitHub has a timeout, and GitHub not answering is a 503, not a refusal

  Scenario: The clean-up's in_use list has a timeout, and one that times out is skipped
    Then the clean-up's in_use list has a timeout, and one that times out is skipped

  Scenario: GitHub that can't be reached at all is a 503 too
    Then GitHub that can't be reached at all is a 503 too

  Scenario: Each call to GitHub is a record of github.repo-ops check-push, tried once, as a person waits on it
    Then each call to GitHub is a record of github.repo-ops check-push, tried once, as a person waits on it

  Scenario: A request's records go to the call log in one call, handed to waitUntil so the answer doesn't wait
    Then a request's records go to the call log in one call, handed to waitUntil so the answer doesn't wait

  Scenario: Without the binding the records are let go, and nothing is written to the bucket
    Then without the binding the records are let go, and nothing is written to the bucket

  Scenario: The calls-storage tenant is the call log's buffer: only ingest reads, writes or deletes through the API
    Then the calls-storage tenant is the call log's buffer: only ingest reads, writes or deletes through the API

  Scenario: The convergence engine's buffers, need-states and calls-convergence-engine, only it and ingest write
    Then the convergence engine's buffers, need-states and calls-convergence-engine, only it and ingest write

  Scenario: The calls-release-controlplane tenant is a call-log buffer both release deployments write
    Then the calls-release-controlplane tenant is a call-log buffer both release deployments write
