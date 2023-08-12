# Changelog

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
