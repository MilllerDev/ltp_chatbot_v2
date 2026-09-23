defmodule LtpChatbotWeb.SessionTokenTest do
  use ExUnit.Case, async: true

  alias LtpChatbotWeb.SessionToken

  describe "sign/2 and verify/2" do
    test "genera un token firmado válido y extrae sus claims" do
      session_id = Ecto.UUID.generate()
      token = SessionToken.sign(session_id, "anon")

      assert is_binary(token)
      assert {:ok, claims} = SessionToken.verify(token)
      assert claims.session_id == session_id
      assert claims.tier == "anon"
    end

    test "soporta diferentes tiers en la firma" do
      session_id = Ecto.UUID.generate()
      token = SessionToken.sign(session_id, "identified")

      assert {:ok, claims} = SessionToken.verify(token)
      assert claims.session_id == session_id
      assert claims.tier == "identified"
    end

    test "rechaza un token adulterado o con firma corrupta" do
      session_id = Ecto.UUID.generate()
      token = SessionToken.sign(session_id, "anon")
      tampered_token = token <> "_adulterado"

      assert {:error, :invalid} = SessionToken.verify(tampered_token)
    end

    test "rechaza un token expirado cuando excede max_age" do
      session_id = Ecto.UUID.generate()
      token = SessionToken.sign(session_id, "anon")

      assert {:error, :expired} = SessionToken.verify(token, -1)
    end

    test "rechaza tokens no binarios o nil" do
      assert {:error, :invalid} = SessionToken.verify(nil)
      assert {:error, :invalid} = SessionToken.verify(12345)
    end
  end
end
