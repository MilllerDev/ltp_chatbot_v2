defmodule LtpChatbot.Sessions.Session do
  @moduledoc """
  Ecto schema for a conversational web session.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @tiers ~w(anon identified verified)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          user_id: integer() | nil,
          tier: String.t(),
          origin: String.t(),
          last_seq: non_neg_integer(),
          last_seen_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "web_sessions" do
    field :user_id, :integer
    field :tier, :string, default: "anon"
    field :origin, :string
    field :last_seq, :integer, default: 0
    field :last_seen_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :tier, :origin])
    |> validate_required([:tier, :origin])
    |> validate_inclusion(:tier, @tiers)
    |> validate_length(:origin, max: 255)
    |> put_change(:last_seq, 0)
    |> put_change(:last_seen_at, DateTime.utc_now())
  end

  def touch_changeset(session, attrs \\ %{}) do
    session
    |> cast(attrs, [:last_seen_at])
    |> put_change(:last_seen_at, DateTime.utc_now())
  end
end
