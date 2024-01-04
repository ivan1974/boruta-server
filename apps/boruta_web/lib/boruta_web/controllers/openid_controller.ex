defmodule BorutaWeb.OpenidController do
  use BorutaWeb, :controller

  alias BorutaWeb.OauthView

  def well_known(conn, _params) do
    conn
    |> put_view(OauthView)
    |> render("well_known.json", routes: Routes)
  end

  def openid_credential_issuer(conn, _params) do
    conn
    |> put_view(OauthView)
    |> render("openid_credential_issuer.json", routes: Routes)
  end
end
