defmodule LtpChatbotWeb.MessageSerializer do
  @moduledoc "Converts domain messages into Phoenix transport payloads."

  alias LtpChatbot.Sessions.Message

  def serialize(%Message{} = message) do
    serialize(%{
      seq: message.seq,
      direction: message.direction,
      client_msg_id: message.client_msg_id,
      body: message.body,
      inserted_at: message.inserted_at
    })
  end

  def serialize(message) when is_map(message) do
    %{
      seq: Map.get(message, :seq) || Map.get(message, "seq"),
      direction: normalize_direction(Map.get(message, :direction) || Map.get(message, "direction")),
      client_msg_id: Map.get(message, :client_msg_id) || Map.get(message, "client_msg_id"),
      body: Map.get(message, :body) || Map.get(message, "body", %{}),
      inserted_at: serialize_timestamp(Map.get(message, :inserted_at) || Map.get(message, "inserted_at"))
    }
  end

  defp normalize_direction(direction) when is_atom(direction), do: Atom.to_string(direction)
  defp normalize_direction(direction), do: direction

  defp serialize_timestamp(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp serialize_timestamp(timestamp), do: timestamp
end
