# Changelog

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
- Added `__edge__/0` to all edges to allow checking if a schema is an edge
- Check for collection doesn't exist on execute/5 for functions such as `Repo.all(User)`
- Added credo config

## 0.6.5

- Changes to GitHub Actions workflow
- Added & fixed some documentation
- Added `collection_exists?/3` function to ArangoXEcto
Checking a document collection exists
```elixir
iex> ArangoXEcto.collection_exists?(Repo, :users)
true
```  
Checking an edge collection exists
```elixir
iex> ArangoXEcto.collection_exists?(Repo, "my_edge", :edge)
true
```
Checking a system document collection exists does not work
```elixir
iex> ArangoXEcto.collection_exists?(Repo, "_system_test")
false
```

- Added some more unit integration tests



## 0.6.4

Initial Release
