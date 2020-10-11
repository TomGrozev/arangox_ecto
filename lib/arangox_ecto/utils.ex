defmodule ArangoXEcto.Utils do
  @moduledoc """
  Helper methods
  """

  @doc """
  Get system database connection
  """
  @spec get_system_db(keyword()) :: pid()
  def get_system_db(config) do
    options =
      config
      |> Keyword.merge(
        pool_size: 1,
        database: "_system"
      )

    Arangox.start_link(options)
  end
end
