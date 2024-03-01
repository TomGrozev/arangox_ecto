defmodule ArangoXEcto.Integration.Migration do
  use ArangoXEcto.Migration

  def change do
    create collection(:users) do
      add :first_name, :string, comment: "first_name column"
      add :last_name, :string
      add :gender, :integer
      add :age, :integer
      add :location, :map

      timestamps()
    end

    create collection(:posts) do
      add :title, :string, max_length: 100
      add :counter, :integer
      add :uuid, :uuid
      add :links, :map
      add :intensities, :map
      add :public, :boolean
      add :cost, :decimal
      add :visits, :integer
      add :wrapped_visits, :integer
      add :intensity, :float
      add :posted, :date
      add :read_only, :string

      timestamps(null: true)
    end

    create edge(:posts_users)

    # Add a unique index on uuid. We use this
    # to verify the behaviour that the index
    # only matters if the UUID column is not NULL.
    create unique_index(:posts, [:uuid], comment: "posts index")

    create collection(:permalinks) do
      add :uniform_resource_locator, :string
      add :title, :string
    end

    create unique_index(:permalinks, [:uniform_resource_locator])

    create collection(:comments) do
      add :text, :string, max_length: 100
      add :lock_version, :integer
    end

    create collection(:customs) do
      add :bid, :string
      add :uuid, :uuid
    end

    create unique_index(:customs, [:uuid])

    create edge(:customs_customs)

    create collection(:barebones) do
      add :num, :integer
    end

    create collection(:transactions) do
      add :num, :integer
    end

    create collection(:lock_counters) do
      add :count, :integer
    end

    create collection(:orders) do
      add :item, :map
      add :items, :map
      add :meta, :map
    end

    create edge(:posts_users_composite) do
      timestamps()
    end

    create unique_index(:posts_users_composite, [:_from, :_to])

    create collection(:usecs) do
      add :naive_datetime_usec, :naive_datetime_usec
      add :utc_datetime_usec, :utc_datetime_usec
    end

    create collection(:loggings) do
      add :bid, :string
      add :int, :integer
      add :uuid, :uuid
      timestamps()
    end
  end
end
