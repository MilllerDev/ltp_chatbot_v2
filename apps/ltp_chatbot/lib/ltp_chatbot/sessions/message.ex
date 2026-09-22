defmodule LtpChatbot.Sessions.Message do
  @moduledoc """
  Ecto schema for an ordered message belonging to a web session.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @directions ~w(in out)

  @type t :: %__MODULE__{
          session_id: Ecto.UUID.t(),
          seq: pos_integer(),
          direction: String.t(),
          client_msg_id: Ecto.UUID.t() | nil,
          body: map(),
          inserted_at: DateTime.t() | nil
        }

  @primary_key false
  @foreign_key_type :binary_id

  schema "web_messages" do
    field :session_id, :binary_id, primary_key: true
    field :seq, :integer, primary_key: true
    field :direction, :string
    field :client_msg_id, :binary_id
    field :body, :map
    field :inserted_at, :utc_datetime_usec
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:session_id, :seq, :direction, :client_msg_id, :body])
    |> validate_required([:session_id, :seq, :direction, :body])
    |> validate_number(:seq, greater_than: 0)
    |> validate_inclusion(:direction, @directions)
  end
end
