---
name: Bug report
about: Report a reproducible bug in the current release of ArangoXEcto
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: >
        **NOTE:** This form is only for reporting _reproducible bugs_ in a current ArangoXEcto
        version. If you're having trouble with installation or just looking for
        assistance with using ArangoXEcto, please visit our
        [discussion forum](https://github.com/TomGrozev/arangox_ecto/discussions) instead.
  - type: input
    attributes:
      label: ArangoXEcto version
      description: What version of ArangoXEcto are you currently running?
      placeholder: v1.0.0
    validations:
      required: true
  - type: input
    attributes:
      label: Elixir and OTP version
      description: What version of Elixir and OTP are you currently running?
      placeholder: 1.12.0
    validations:
      required: true
  - type: input
    attributes:
      label: Ecto version
      description: What version of Ecto are you currently running?
      placeholder: 3.0.0
    validations:
      required: true
  - type: input
    attributes:
      label: ArangoDB version
      description: What version of ArangoDB are you currently running?
      placeholder: 3.6.3
    validations:
      required: true
  - type: textarea
    attributes:
      label: Steps to Reproduce
      description: >
        Describe in detail the exact steps that someone else can take to
        reproduce this bug using the current stable release of ArangoXEcto. Begin with the
        creation of any necessary database objects and call out every operation being
        performed explicitly.
      placeholder: |
        1. create user schema
        2. delete post
        3. query user schema
    validations:
      required: true
  - type: textarea
    attributes:
      label: Expected Behavior
      description: What did you expect to happen?
      placeholder: The use should be returned
    validations:
      required: true
  - type: textarea
    attributes:
      label: Observed Behavior
      description: What happened instead?
      placeholder: An exception was raised
    validations:
      required: true
  - type: textarea
    attributes:
      label: Additional Context
      description: Any additional information
