defmodule ArangoXEcto.Integration.Migration do
  use ArangoXEcto.Migration

  alias ArangoXEcto.View.Link

  def change do
    create collection(:users) do
      add :first_name, :string, comment: "first_name column"
      add :last_name, :string
      add :gender, :integer
      add :age, :integer
      add :location, :map

      timestamps()
    end

    create collection(:users, prefix: "tenant1") do
      add :first_name, :string, comment: "first_name column"
      add :last_name, :string
      add :gender, :integer
      add :age, :integer
      add :location, :map

      timestamps()
    end

    create view(:user_search, commitIntervalMsec: 1, consolidationIntervalMsec: 1) do
      add_sort(:created_at, :desc)
      add_sort(:first_name)

      add_store([:first_name, :last_name], :none)

      add_link("users", %Link{
        includeAllFields: true,
        fields: %{
          last_name: %Link{
            analyzers: [:identity, :text_en]
          }
        }
      })
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
      add :intensity, :float
      add :posted, :date
      add :read_only, :string

      timestamps(null: true)
    end

    create edge(:post_user)
    create edge(:user_user)

    create edge(:posts_users) do
      add :type, :string
    end

    create edge(:posts_users_options, keyOptions: %{type: :uuid}) do
      add :type, :string
    end

    create unique_index(:posts_users_options, [:type])

    create edge(:user_content)

    create edge(:post_classes)

    create collection(:permalinks) do
      add :uniform_resource_locator, :string
      add :title, :string
    end

    create unique_index(:permalinks, [:uniform_resource_locator])

    create collection(:comments, keyOptions: %{type: :uuid}) do
      add :text, :string, max_length: 100
      add :lock_version, :integer
    end

    create unique_index(:comments, [:text])

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
