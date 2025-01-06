# Searching with ArangoSearch

ArangoDB uses ArangoSearch to index collections to improve the searchability of them. With this
you can do things like have multiple collections in one "view". A view is a concept that is
essentially take one or more collections and indexes it using whatever "analyzer(s)" you choose to
apply.

To query a View you just use it as if you were using any other collection schema. It will return
the results the same as if you were querying that schema.

To create a View it is very similar to how you create a collection schema. The following will
create a view that has primary sorts on :created_at and :name, it will store the :email and the
:first_name & :last_name fields. Most importantly it will create a link to the `MyApp.Users`
schema and set the analyzer for the `:name` field to `:text_en`. Some options can be set also.

    defmodule MyApp.UserSearch do
      use ArangoXEcto.View

      alias ArangoXEcto.View.Link

      view "user_search" do
        primary_sort :created_at, :desc
        primary_sort :name

        store_value [:email], :lz4
        store_value [:first_name, :last_name], :none

        link MyApp.Users, %Link{
          includeAllFields: true,
          fields: %{
            name: %Link{
              analyzers: [:text_en]
            }
          }
        }

        options  [
          primarySortCompression: :lz4
        ]
      end
    end

Querying is done exactly the same as a normal schema except the result will not be a struct.

    iex> Repo.all(MyApp.UsersView)
    [%{first_name: "John", last_name: "Smith"}, _]

You can find out more info in the `ArangoXEcto.View` module.

To query using the search function you can use the `ArangoXEcto.Query.search/3` and
`ArangoXEcto.Query.or_search/3` functions. For example, if we wanted to search using the text
analyzer we could do the following.

    import ArangoXEcto.Query

    from(UsersView)
    |> search([uv], fragment("ANALYZER(? == ?, \\"text_en\\")", uv.first_name, "John"))
    |> Repo.all()
