defmodule BorutaWeb.Openid.CredentialController do
  @behaviour Boruta.Openid.CredentialApplication
  use BorutaWeb, :controller

  alias Boruta.Oauth.Error
  alias Boruta.Openid
  alias BorutaWeb.OauthView

  def credential(conn, params) do
    Openid.credential(conn, params, __MODULE__)
  end

  @impl Boruta.Openid.CredentialApplication
  def credential_created(conn, credential_response) do
    conn
    |> put_view(OauthView)
    |> render("credential.json", credential_response: credential_response)
  end

  @impl Boruta.Openid.CredentialApplication
  def credential_failure(conn, %Error{
        status: status,
        error: error,
        error_description: error_description
      }) do
    conn
    |> put_status(status)
    |> put_view(OauthView)
    |> render("error.json", error: error, error_description: error_description)
  end
end
