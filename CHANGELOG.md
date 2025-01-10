# Changelog

## 2.0.0

This is a big release with a lot of changes and has been over a year in the
making. I am so glad it is finally finished :)

There are many breaking changes and the API to lots of functions have changed.
Please make sure to check the changes in the docs.

Some of the commits were big and does not follow good commit practices. I know
some might say "why didn't you do this progressively?" and yes that is correct
it should have been done that way. However, I have been very busy over the past
year which is why it took so long to get this version out of the door. I also
got a new computer and moved house so sometimes rules go out of the window.

Static mode is now the default as it is more production ready. Dynamic mode can
now be set by setting `:static` to false in your config.

_This release now requires Ecto 3.12 and Arangox 0.6.0 as a minimum._

### Enhancements

#### Migrations improvements

Complete rework of migrations functionality to support full migrations including
using ArangoDB schemas for database level validation. (#73)

- All database actions are done through migrations
  - This includes create, modify, rename and remove functions for Collections,
    Indexes, Views and Analyzers.
- Add JSON schema generation from migrations for database level validation
- Migrations are run in a transaction
- Commands updated to not conflict with other database adapters
  - `mix ecto.migrate.arango` renamed to `mix arango.migrate`, same for other
    commands
  - Use the `execute_ddl/3` function in the adapter to support other
    database adapters
- Type of collection is set in options rather then a parameter
- Migrations can be run as part of a supervision tree (for when doing
  releases)
- Option to cast migration version to integer (default false)
- Supports add, remove, modify, add_if_not_exists and remove_if_exists
  migration commands
- Support embedded fields and an array of embedded fields
- Supports reversing migrations, hence can use just the `change/0` function in
  migrations rather than needing to use both `up/0` and `down/0`

#### Graphing relations improvements

Complete rework of graph relationships (#39).

This replaces the many_to_many usage with a purpose build Ecto association.
The primary difference is that this allows for multiple different
schemas to be related, i.e. it is polymorphic. I.e. A User could have
a field called `:my_content` that could have either Posts or Comments
associated. This lines up better with how ArangoDB works.

To get this working it required a few tricks and in some cases it
required a copy and reimplementation of some of Ecto's functions. For
example, a new `ArangoXEcto.Changeset` module was created and must be
imported to use the `cast_graph/3` and `put_graph/4`. These two
functions are essentially the same as the `cast_assoc/3` and
`put_assoc/4` functions that Ecto provide, except it will allow for
multiple types to be applied and supports the mapping by the fields in
attributes.

In addition to this the EdgeMany association was created so that it supports
multiple schemas being passed. This is so that edges can have multiple schemas
in the from and to, which lines up more closely with how ArangoDB functions.

- `ArangoXEcto.create_edge/4` supports a list of edge modules
- Ensure that the from and to schemas exist in an edge definition
- Add `ArangoXEcto.Query.graph/5` macro to perform graph queries through Ecto
  queries
- Added the `ArangoXEcto.Changeset.cast_graph/3` and
  `ArangoXEcto.Changeset.put_graph/4` functions
- Add the `ArangoXEcto.Association.EdgeMany` and `ArangoXEcto.Association.Graph`
  association definitions
- Add `ArangoXEcto.preload/4` function to support preloading graph associations
- Removed the `one_outgoing/3`, `one_incoming/3` and `build_foreign_key/1` functions
  since they were not used and essentially just reimplement Ecto functions.

#### Other Enhancements

- Enhance transaction functionality and add rollback ability
- Added the ability to stream queries using ArangoDB's cursors
- Improve logging and telemetry (Based on the `ecto_sql` implementation)
  - Add logging and telemetry handlers to query, insert, update and delete
    functions
  - Supports transactions and AQL queries
- Add caching of queries in Ecto
- Improve connection handling with database between Ecto and adapter
- View links validation is moved to after compile to improve validation checks
- Static mode is now the default
  - Added checks for functions that can only be run in static/dynamic mode
- Add support for typecasting in Ecto queries through `Ecto.Query.API.type/2`
- Add `ArangoXEcto.Sandbox` for integration testing (similar to the `ecto_sql`
  implementation)
- Supports running alongside other database adapters, such as `ecto_sql`
  - Added dummy implementation of functions that `ecto_sql` uses
- Add support for fragments (and splicing) in queries that are then converted
  into AQL
- Removed the already deprecated `ArangoXEcto.raw_to_struct/2` function
- Update to support Ecto 3.12 (now minimum required version)

### Fixes

- Fix typespec for `t:mod/0` in `ArangoXEcto`
- ArangoSearch type is forced to be "arangosearch"
- Rename `is_edge?/1`, `is_document?/1` and `is_view?/1` to remove the is\_
- Type checking functions (the ones mentioned above) will ensure that the module
  being checked is loaded before checking
- Fix type validation on analyzer creation
- Resolve `:database` option passed to `ArangoXEcto.query/4` not working
- Allow nil to be passed to type loaders in adapter
- Make prefix option work universally across all database functions
- Update mix formatter configuration
- Clean up `ArangoXEcto.load/2` function
- Move `:fullCount` property to the adapter so that it is used for all
  connections
- Add check so that mix tasks are only run on ArangoXEcto repos
- Remove `ArangoXEcto.Utils` module
- Fix issue where collection indexes were not being created in dynamic mode
- Removed some unused clauses in `ArangoXEcto.Types.GeoJSON`
- Add missing tests for mix tasks (excluded by default)
- Migrate formatting to preferred formatting for elixir 1.18 (using mix format
  --migrate)
- Various cleanups of the codebase
- Various test fixes

### Doc changes

- Add basic guides
- Significant improvement to documentation and typespec coverage

### Repo changes

- Update dependencies
- Improve test coverage to at least 80%
  - This was a big rework to include more tests and really ensuring
    functionality works
- Update doctor configuration
- Ignore tmp directory in git repo for when tests are run
- Update CI pipeline
  - Update elixir and otp versions
  - Make arangodb version explicit to 3.11
- Add coveralls for test coverage checking

## 1.3.1

### Fixes

- Fix for migrations failing due to wrong argument being passed (thanks @ilourt)

## 1.3.0

_This release now requires Ecto 3.9 and Arangox 0.5.5 as a minimum._

### Enhancements

- Add Arango Search capability (#60)
  - Added `ArangoXEcto.View` definition
  - Ecto querying of views
  - Add search extensions for Ecto Querying in `ArangoXEcto.Query` (_BREAKING CHANGE_ requires Ecto 3.9)
  - Adds analyzer definition for management in code
  - Add view and analyzer migration capability to `ArangoXEcto.Migration`
- Allow `ArangoXEcto.load/2` to load from multiple different schmeas
- Add ability to sort using fragments
- Add multi-tenancy functionality (#25) using Ecto `:prefix` option
  - Adds the ability to pass the :prefix option for CRUD operations
  - Adds ArangoXEcto.get_prefix_database/2 to get the database name
  - Adds querying prefix option (_BREAKING CHANGE_ requires Arangox >= 0.5.5)

### Fixes

- Fix write operation on AQL query not working for delete
- Fix static mode tests using a static mode repo
- Add missing query tests #61 (thanks @mpoeter)
- Adapt AQL query builder for Ecto 3.10 which introduced LimitExpr #61 (thanks @mpoeter)

### Doc changes

- Add Arango Search related documentation

## 1.2.1

### Fixes

- Fix for Repo.exists?/1 function not working correctly (thanks @ilourt)
- Resolved #55 - ability to use custom types (e.g. Enum) (thanks @mpoeter)
- Fix for when dumping lists
- Fix for #58 - preloading edge collection's `_to` and `_from` to reference `_id`

### Doc changes

- Added clarifying documentation (+ test) for write operations of `ArangoXEcto.aql_query/4` (thanks @mrsisk)

### Repo Changes

- Update test versions

## 1.2.0

### Enhancements

- Added `ArangoXEcto.load/2` which will load deep schemas (so associations will work)
- Added ability to use Ecto's count and aggregate functionality
- Added ability to use Ecto's datetime helper functions (e.g. `:datetime_add`)
- Separate `aql_query/4` with `aql_query!/4` raising an error on fail

### Fixes

- Fix for #49 - unique_constraint not recognized (thanks @jamilabreu)
- Prevent warnings for `__id__` field on creation
- Fix for when an update is applied to a non-existent document `:stale` is raised
- Fix for dates not being queryable using Ecto
- Prevent error thrown when non `_key` filter is supplied to update, resolves #48

### Other Doc Changes

- Added information about one-to-many relationships in the README

### Deprecations

- `ArangoXEcto.raw_to_struct/2` is deprecated in favor of `ArangoXEcto.load/2` add will be removed in a future version

### Repo Changes

- Include a config file for local git hooks

## 1.1.1

### Fixes

- Fixed `indexes/1` and `options/1` for use in dynamic edge collection creation (closes #46)
- Added logging messages for errors in `indexes/1` and `options/1`
- Add `:name` option for index creation. Fixes issue with phoenix unique constraints
- Fixes on_conflict issue (arango does not support for specific fields, only will replace all no matter which replace option is passed)
- Various tests for changes

## 1.1.0

### Enhancements

- Update `credo` and `git_hooks` dev & test dependencies
- Add ability to pass collection creation options for migrations
- Add tests for migrations
- Use migration module for all collection creation
- Use underscored module name for repo dir to allow for different repo director name (thanks @hengestone)
- Big cleanup of README

#### Dynamic Collection Creation Options

- Add `options/1` macro for dynamic collection creation options
- Add `indexes/1` macro for dynamic collection creation indexes
- Add tests for creation options and indexes

### Fixes

- Clean up some syntax in line with new credo requirements
- Add `doctor` config to remove false positive doc requirements with macros
- Add some missing function docs
- Various refactoring to clean up code
- Fix to remove `Map.reject/2` for support of below Elixir 1.13
- Pass the connection to collection creation to ensure correct repo is used
- Fix a race condition in testing caused by same named collections for different tests
- Require `DB_ENDPOINT` env var for tests

### Repo Changes

- Add Elixir 1.13 to testing matrix
- Use `erlef/setup-beam` for ci and deploy GH actions (thanks @kianmeng)
- Add develop branch to ci GH action

## 1.0.0

### Enhancements

- Added api_query/3 function for direct Arango API queries
- Added lots of test cases for Ecto base functionality
- Added missing test cases that should have been previously included
- Adds ability to do subqueries in AQL queries
- Improve migration template
- Rework migration command
- Removed `create_edge/6` function

#### Graph Relationships

- Complete rework of Edge relationships to conform to Ecto standards
  E.g.

```elixir
defmodule MyProject.User do
  use ArangoXEcto.Schema
  schema "users" do
    field :name, :string
    # Will use the automatically generated edge
    outgoing :posts, MyProject.Post
    # Will use the UserPosts edge
    outgoing :posts, MyProject.Post, edge: MyProject.UserPosts
    # Creates foreign key
    one_outgoing :main_post, MyProject.Post
  end
end

defmodule MyProject.Post do
  use ArangoXEcto.Schema
  schema "posts" do
    field :title, :string
    # Will use the automatically generated edge
    incoming :users, MyProject.User
    # Will use the UserPosts edge
    incoming :users, MyProject.User, edge: MyProject.UserPosts
    # Stores foreign key id in schema
    one_incoming :user, MyProject.User
  end
end
```

- Adds one-to-one relation (not a graph relation, stores as an ID in field)
- Add graph tests
- Automatically insert `_id` field into schemas when interacting with edges, saved in `:__id__` attributed
- Documentation for graph functionality

### Geo Functionality

- Added Geo functionality with GeoJSON support
- Added `ArangoXEcto.Types.GeoJSON` type
- Added `:geo` package dependency
- Added Geo related helper functions to manage Geo data in `ArangoXEcto.GeoData`
- Documentation for Geo functionality

### Static or Dynamic Collection Management

- Added the ability to dynamically create collections or require migrations
- Added `:static` boolean config option (default if false)
- Added tests for static/dynamic functionality

### Fixes

- Fixed typespec for aql_query/4 (PR #27, thanks @bodbdigr)
- Fixed missed ArangoX version api change in `Mix.ArangoXEcto`
- Fixed incorrect length return on writing queries (i.e. updates and deletes)
- Fixed Arango storing integer as float
- Complete rewrite of setup command to fix incorrect setup processes and messages
- Fixed a race condition in edge creation
- Added missing specs
- Some other minor fixes that I cbf adding because nobody had experienced it

### Repo Changes

- Updated ISSUE templates

## 0.7.2

### Fixes

- Updates deps to latest
- Update to ecto 3.6

## 0.7.1

### Fixes

- Fix warnings in typecasting
- Fix ecto version requirement issue with phoenix

## 0.7.0

### Enhancements

- Add support for database transactions
- Decimal support in database
- Add schema_type/1 for non error thrown version
- Additional testing

### Fixes

- Fixes duplicate migration entries
- Stops running migrations again
- Additional catch in core functions
- Fix ID key conversion

## 0.6.9

- (#12) Ecto 3.5 version bump
- Format fixes

## 0.6.8

- (#10) Fixed mix task conflict with ecto
- (#8) Fixes some incorrect documentation
- Bump versions of dependencies

## 0.6.7

- Various documentation fixes (thanks @kianmeng)
- Allows ecto queries by `_id` as well as `_key`
- Fixed a bug when passing config in migrations ignored anything except the `:endpoints` option
- Fixed a bug when passing a struct to `edge_module/3`

## 0.6.6

- Added this file
- Better organised GitHub Actions
- Allow collection_exists?/3 to use a connection as well as repo
- Added is_edge?/1, is_document?/1 and schema_type!/1
  Checking if is a module is an edge

```elixir
iex> ArangoXEcto.is_edge?(MyApp.RealEdge)
true
```

Checking if is a module is a document collection

```elixir
iex> ArangoXEcto.is_document?(MyApp.Users)
true
```

Checking a schema type

```elixir
iex> ArangoXEcto.schema_type!(MyApp.RealEdge)
:edge
```

- Adde
