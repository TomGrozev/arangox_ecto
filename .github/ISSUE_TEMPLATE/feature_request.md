---
name: Feature request
about: Suggest an idea for this project
labels: ["enhancement"]
body:
  - type: markdown
    attributes:
      value: >
        **NOTE:** This form is only for submitting well-formed proposals to extend or modify
        ArangoXEcto in some way. If you're trying to solve a problem but can't figure out how, or if
        you still need time to work on the details of a proposed new feature, please start a
        [discussion](https://github.com/TomGrozev/arangox_ecto/discussions) instead.
  - type: input
    attributes:
      label: ArangoXEcto version
      description: What version of ArangoXEcto are you currently running?
      placeholder: v1.0.0
    validations:
      required: true
  - type: dropdown
    attributes:
      label: Feature type
      options:
        - API change
        - New functionality
        - Change to existing functionality
    validations:
      required: true
  - type: textarea
    attributes:
      label: Proposed functionality
      description: >
        Describe in detail the new feature or behavior you are proposing. Include any specific changes
        to work flows, schema formats, and/or API functions. The more detail you provide here, the
        greater chance your proposal has of being discussed. Feature requests which don't include an
        actionable implementation plan will be rejected.
    validations:
      required: true
  - type: textarea
    attributes:
      label: Use case
      description: >
        Explain how adding this functionality would benefit ArangoXEcto users. What need does it address?
    validations:
      required: true
  - type: textarea
    attributes:
      label: Version changes
      description: >
        Note any changes to any version requirements, i.e. Ecto, ArangoDB, Elixir, etc. This includes
        any dependencies that need to change version.
  - type: textarea
    attributes:
      label: External dependencies
      description: >
        List any new dependencies on external libraries or services that this new feature would
        introduce. For example, does the proposal require the installation of a new Hex package?
        (Not all new features introduce new dependencies.)
  - type: textarea
    attributes:
      label: Additional Context
      description: Any additional information
