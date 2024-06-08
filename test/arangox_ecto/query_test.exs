defmodule ArangoXEctoTest.QueryTest do
  use ExUnit.Case
  @moduletag :supported

  import Ecto.Query
  import ArangoXEcto.Query, only: [search: 2, search: 3]

  alias ArangoXEcto.Integration.{Comment, Post, User, UsersView}
  alias Ecto.Query.Planner

  defp aql(query, operation \\ :all, counter \\ 0) do
    adapter = ArangoXEcto.Adapter
    query = Planner.ensure_select(query, operation == :all)
    {query, _params, _key} = Planner.plan(query, operation, adapter)
    {query, _select} = Planner.normalize(query, operation, adapter, counter)
    {_cache, {_id, prepared}} = adapter.prepare(operation, query)
    prepared
  end

  describe "create AQL query" do
    test "with select clause" do
      assert aql(from(u in User)) =~
               "FOR u0 IN `users` RETURN [ u0.`_key`, u0.`_id`, u0.`first_name`, u0.`last_name`, u0.`gender`, u0.`age`, u0.`location`, u0.`class`, u0.`items`, u0.`inserted_at`, u0.`updated_at` ]"

      assert aql(from(u in User, select: u.first_name)) =~
               "FOR u0 IN `users` RETURN [ u0.`first_name` ]"

      assert aql(from(u in User, select: [u.first_name, u.gender])) =~
               "FOR u0 IN `users` RETURN [ u0.`first_name`, u0.`gender` ]"
    end

    test "with select distinct" do
      assert aql(from(u in User, select: u.first_name, distinct: true)) =~
               "FOR u0 IN `users` RETURN DISTINCT [ u0.`first_name` ]"
    end

    test "with where clause" do
      assert aql(from(u in User, where: u.first_name == "Joe", select: u.first_name)) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') RETURN [ u0.`first_name` ]"

      assert aql(from(u in User, where: not (u.first_name == "Joe"), select: u.first_name)) =~
               "FOR u0 IN `users` FILTER (NOT (u0.`first_name` == 'Joe')) RETURN [ u0.`first_name` ]"

      assert aql(from(u in User, where: like(u.first_name, "J%"), select: u.first_name)) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` LIKE 'J%') RETURN [ u0.`first_name` ]"

      first_name = "Joe"

      assert aql(from(u in User, where: u.first_name == ^first_name)) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == @1) RETURN [ u0.`_key`, u0.`_id`, u0.`first_name`, u0.`last_name`, u0.`gender`, u0.`age`, u0.`location`, u0.`class`, u0.`items`, u0.`inserted_at`, u0.`updated_at` ]"

      assert aql(from(u in User, where: u.first_name == "Joe" and u.gender == :male)) =~
               "FOR u0 IN `users` FILTER ((u0.`first_name` == 'Joe') && (u0.`gender` == 0)) RETURN [ u0.`_key`, u0.`_id`, u0.`first_name`, u0.`last_name`, u0.`gender`, u0.`age`, u0.`location`, u0.`class`, u0.`items`, u0.`inserted_at`, u0.`updated_at` ]"

      assert aql(from(u in User, where: u.first_name == "Joe" or u.gender == :female)) =~
               "FOR u0 IN `users` FILTER ((u0.`first_name` == 'Joe') || (u0.`gender` == 1)) RETURN [ u0.`_key`, u0.`_id`, u0.`first_name`, u0.`last_name`, u0.`gender`, u0.`age`, u0.`location`, u0.`class`, u0.`items`, u0.`inserted_at`, u0.`updated_at` ]"
    end

    test "with search clause" do
      assert aql(
               from(uv in UsersView, select: uv.first_name)
               |> search([uv], uv.first_name == "Joe")
             ) =~
               "FOR u0 IN `user_search` SEARCH (u0.`first_name` == 'Joe') RETURN [ u0.`first_name` ]"

      assert aql(
               from(uv in UsersView, select: uv.first_name)
               |> search([uv], fragment("ANALYZER(? == ?, \"identity\")", uv.first_name, "John"))
             ) =~
               "FOR u0 IN `user_search` SEARCH (ANALYZER(u0.`first_name` == 'John', \"identity\")) RETURN [ u0.`first_name` ]"

      query =
        from(UsersView)
        |> search(last_name: "Smith")
        |> order_by([uv], fragment("BM25(?)", uv))
        |> select([uv], {uv.first_name, fragment("BM25(?)", uv)})

      assert aql(query) =~
               "FOR u0 IN `user_search` SEARCH (u0.`last_name` == 'Smith') SORT BM25(u0) RETURN [ u0.`first_name`, BM25(u0) ]"
    end

    test "with fragments in where clause" do
      assert aql(from(o in "orders", select: o._key, where: fragment("?.price", o.item) > 10)) =~
               "FOR o0 IN `orders` FILTER (o0.`item`.price > 10) RETURN [ o0.`_key` ]"
    end

    test "with 'in' operator in where clause" do
      assert aql(from(p in "posts", where: p.title in [], select: p.title)) =~
               "FOR p0 IN `posts` FILTER (FALSE) RETURN [ p0.`title` ]"

      assert aql(from(p in "posts", where: p.title in ["1", "2", "3"], select: p.title)) =~
               "FOR p0 IN `posts` FILTER (p0.`title` IN ['1','2','3']) RETURN [ p0.`title` ]"

      assert aql(from(p in "posts", where: p.title not in [], select: p.title)) =~
               "FOR p0 IN `posts` FILTER (NOT (FALSE)) RETURN [ p0.`title` ]"
    end

    test "with 'in' operator and pinning in where clause" do
      assert aql(from(p in "posts", where: p.title in ^[], select: p.title)) =~
               "FOR p0 IN `posts` FILTER (p0.`title` IN @1) RETURN [ p0.`title` ]"

      assert aql(from(p in "posts", where: p.title in ["1", ^"hello", "3"], select: p.title)) =~
               "FOR p0 IN `posts` FILTER (p0.`title` IN ['1',@1,'3']) RETURN [ p0.`title` ]"

      assert aql(from(p in "posts", where: p.title in ^["1", "hello", "3"], select: p.title)) =~
               "FOR p0 IN `posts` FILTER (p0.`title` IN @1) RETURN [ p0.`title` ]"

      assert aql(
               from(
                 p in "posts",
                 where: p.title in ^["1", "hello", "3"] and p.text != ^"",
                 select: p.title
               )
             ) =~
               "FOR p0 IN `posts` FILTER (p0.`title` IN @1 && (p0.`text` != @2)) RETURN [ p0.`title` ]"
    end

    test "with order by clause" do
      assert aql(from(u in User, order_by: u.first_name, select: u.first_name)) =~
               "FOR u0 IN `users` SORT u0.`first_name` RETURN [ u0.`first_name` ]"

      assert aql(from(u in User, order_by: [desc: u.first_name], select: u.first_name)) =~
               "FOR u0 IN `users` SORT u0.`first_name` DESC RETURN [ u0.`first_name` ]"

      assert aql(
               from(u in User, order_by: [desc: u.first_name, asc: u.age], select: u.first_name)
             ) =~
               "FOR u0 IN `users` SORT u0.`first_name` DESC, u0.`age` RETURN [ u0.`first_name` ]"
    end

    test "with limit and offset clauses" do
      assert aql(from(u in User, limit: 10)) =~
               "FOR u0 IN `users` LIMIT 10 RETURN [ u0.`_key`, u0.`_id`, u0.`first_name`, u0.`last_name`, u0.`gender`, u0.`age`, u0.`location`, u0.`class`, u0.`items`, u0.`inserted_at`, u0.`updated_at` ]"

      assert aql(from(u in User, limit: 10, offset: 2)) =~
               "FOR u0 IN `users` LIMIT 2, 10 RETURN [ u0.`_key`, u0.`_id`, u0.`first_name`, u0.`last_name`, u0.`gender`, u0.`age`, u0.`location`, u0.`class`, u0.`items`, u0.`inserted_at`, u0.`updated_at` ]"

      assert_raise Ecto.QueryError, ~r"offset can only be used in conjunction with limit", fn ->
        aql(from(u in User, offset: 2))
      end
    end

    test "with join" do
      assert aql(
               from(
                 c in Comment,
                 join: p in Post,
                 on: p.id == c.post__key,
                 select: {p.title, c.text}
               )
             ) =~
               "FOR c0 IN `comments` FOR p1 IN `posts` FILTER p1.`_key` == c0.`post__key` RETURN [ p1.`title`, c0.`text` ]"
    end

    test "with is_nil in where clause" do
      assert aql(from(u in User, select: u.id, where: is_nil(u.first_name))) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == NULL) RETURN [ u0.`_key` ]"
    end

    test "with datetime_add in where clause" do
      num_days = 5

      assert aql(
               from(u in User,
                 select: u.id,
                 where: datetime_add(u.inserted_at, ^num_days, "day") < ^DateTime.utc_now()
               )
             ) =~
               "FOR u0 IN `users` FILTER (DATE_ADD(u0.`inserted_at`, @1, 'day') < @2) RETURN [ u0.`_key` ]"
    end

    test "with date_add in where clause" do
      assert aql(
               from(p in Post,
                 select: p.id,
                 where: date_add(p.posted, p.counter, "day") < ^Date.utc_today()
               )
             ) =~
               "FOR p0 IN `posts` FILTER (date_add(p0.`posted`, p0.`counter`, 'day') < @1) RETURN [ p0.`_key` ]"
    end

    test "with type casting" do
      assert aql(
               from(p in Post,
                 select: type(p.id, :integer)
               )
             ) =~ "FOR p0 IN `posts` RETURN [ TO_NUMBER(p0.`_key`) ]"
    end
  end

  describe "create remove query" do
    test "without returning" do
      assert aql(from(u in User, where: u.first_name == "Joe"), :delete_all) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') REMOVE u0 IN `users`"
    end

    test "with returning" do
      assert aql(from(u in User, where: u.first_name == "Joe", select: u), :delete_all) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') REMOVE u0 IN `users` RETURN [ OLD.`_key`, OLD.`_id`, OLD.`first_name`, OLD.`last_name`, OLD.`gender`, OLD.`age`, OLD.`location`, OLD.`class`, OLD.`items`, OLD.`inserted_at`, OLD.`updated_at` ]"

      assert aql(
               from(u in User, where: u.first_name == "Joe", select: u.first_name),
               :delete_all
             ) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') REMOVE u0 IN `users` RETURN [ OLD.`first_name` ]"
    end
  end

  describe "create update query" do
    test "without returning" do
      assert aql(
               from(u in User, where: u.first_name == "Joe", update: [set: [gender: :other]]),
               :update_all
             ) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') UPDATE u0 WITH {`gender`: 2} IN `users`"

      assert aql(
               from(u in User, where: u.first_name == "Joe", update: [inc: [age: 2]]),
               :update_all
             ) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') UPDATE u0 WITH {`age`: u0.`age` + 2} IN `users`"
    end

    test "with returning" do
      assert aql(
               from(u in User,
                 where: u.first_name == "Joe",
                 select: u,
                 update: [set: [age: 42]]
               ),
               :update_all
             ) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') UPDATE u0 WITH {`age`: 42} IN `users` RETURN [ NEW.`_key`, NEW.`_id`, NEW.`first_name`, NEW.`last_name`, NEW.`gender`, NEW.`age`, NEW.`location`, NEW.`class`, NEW.`items`, NEW.`inserted_at`, NEW.`updated_at` ]"

      assert aql(
               from(u in User,
                 where: u.first_name == "Joe",
                 select: u.first_name,
                 update: [set: [age: 42]]
               ),
               :update_all
             ) =~
               "FOR u0 IN `users` FILTER (u0.`first_name` == 'Joe') UPDATE u0 WITH {`age`: 42} IN `users` RETURN [ NEW.`first_name` ]"
    end
  end
end
