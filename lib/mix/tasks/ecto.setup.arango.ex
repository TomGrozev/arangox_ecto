defmodule Mix.Tasks.Ecto.Setup.Arango do
  @moduledoc """
  Sets up all necessary aspects of the adapter

  Adds migrations collection in _systems db for migrations and creates the database
  """

  use Mix.Task

  alias Mix.ArangoXEcto, as: Helpers

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("\n=====[ Running ArangoXEcto Setup ]=====")

    Helpers.create_base_database()
    |> process_response(
      {&"1 >> Created database `#{&1}`", "1 >> Database already exists",
       &"1 >> Error creating database, returned Arango API status `#{&1}`"},
      &Helpers.create_migrations/0
    )
    |> process_response(
      {"2 >> Created migrations collection in system database",
       "2 >> System database already has migrations collection",
       &"2 >> Error creating migrations collection, returned Arango API status `#{&1}`"},
      &Helpers.create_migration_document/0
    )
    |> process_response(
      {"3 >> Created migation document. \nSetup Complete",
       "3 >> Migrations collection already contains database document",
       &"3 >> Error creating migration database document, returned Arango API status `#{&1}`"},
      nil
    )
  end

  defp process_response(:fail, _, _), do: :fail

  defp process_response(response, {success_msg, exists_msg, error_msg}, success_func) do
    case response do
      {:ok, pass_arg} ->
        build_msg(success_msg, pass_arg)
        |> Mix.shell().info()

        maybe_run_success_func(success_func)

      :ok ->
        build_msg(success_msg)
        |> Mix.shell().info()

        maybe_run_success_func(success_func)

      {:error, 409} ->
        build_msg(exists_msg)
        |> Mix.shell().info()

        maybe_run_success_func(success_func)

      {:error, status} ->
        build_msg(error_msg, status)
        |> Mix.shell().error()

        :fail
    end
  end

  defp maybe_run_success_func(func) when is_function(func) and not is_nil(func),
    do: func.()

  defp maybe_run_success_func(_), do: :ok

  defp build_msg(func, args \\ [])

  defp build_msg(func, arg) when not is_list(arg), do: build_msg(func, [arg])

  defp build_msg(func, args) when is_function(func),
    do: apply(func, args)

  defp build_msg(msg, _), do: msg
end
