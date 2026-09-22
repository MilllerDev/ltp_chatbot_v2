defmodule LtpChatbot.Repo.Migrations.CreateWebSessionsAndMessages do
  use Ecto.Migration

  def change do
    create table(:web_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :bigint
      add :tier, :string, null: false, default: "anon"
      add :origin, :string, null: false
      add :last_seq, :bigint, null: false, default: 0
      add :last_seen_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:web_sessions, :web_sessions_tier_check,
             check: "tier IN ('anon', 'identified', 'verified')"
           )

    create index(:web_sessions, [:user_id])
    create index(:web_sessions, [:last_seen_at])

    create table(:web_messages, primary_key: false) do
      add :session_id, references(:web_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :seq, :bigint, null: false
      add :direction, :string, null: false
      add :client_msg_id, :binary_id
      add :body, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
    end

    execute(
      "ALTER TABLE web_messages ADD PRIMARY KEY (session_id, seq)",
      "ALTER TABLE web_messages DROP CONSTRAINT web_messages_pkey"
    )

    create constraint(:web_messages, :web_messages_direction_check,
             check: "direction IN ('in', 'out')"
           )

    create unique_index(:web_messages, [:session_id, :client_msg_id],
             name: :web_messages_session_id_client_msg_id_index,
             where: "client_msg_id IS NOT NULL"
           )

    create index(:web_messages, [:session_id, :inserted_at])
  end
end
