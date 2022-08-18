defmodule BorutaIdentityWeb.UserSessionController do
  @behaviour BorutaIdentity.Accounts.SessionApplication

  use BorutaIdentityWeb, :controller

  import BorutaIdentityWeb.Authenticable,
    only: [
      store_user_session: 2,
      get_user_session: 1,
      remove_user_session: 1,
      after_sign_in_path: 1,
      after_sign_out_path: 1,
      client_id_from_request: 1
    ]

  alias BorutaIdentity.Accounts
  alias BorutaIdentity.Accounts.SessionError
  alias BorutaIdentityWeb.TemplateView

  def new(conn, _params) do
    client_id = client_id_from_request(conn)

    Accounts.initialize_session(conn, client_id, __MODULE__)
  end

  def create(conn, %{"user" => user_params}) do
    client_id = client_id_from_request(conn)

    authentication_params = %{
      email: user_params["email"],
      password: user_params["password"]
    }

    Accounts.create_session(conn, client_id, authentication_params, __MODULE__)
  end

  def delete(conn, _params) do
    client_id = client_id_from_request(conn)
    session_token = get_user_session(conn)

    Accounts.delete_session(conn, client_id, session_token, __MODULE__)
  end

  @impl BorutaIdentity.Accounts.SessionApplication
  def session_initialized(%Plug.Conn{} = conn, template) do
    conn
    |> put_layout(false)
    |> put_view(TemplateView)
    |> render("template.html",
      template: template,
      assigns: %{}
    )
  end

  @impl BorutaIdentity.Accounts.SessionApplication
  def user_authenticated(conn, user, session_token) do
    client_id = client_id_from_request(conn)

    :telemetry.execute(
      [:authentication, :log_in, :success],
      %{},
      %{
        sub: user.uid,
        backend: user.backend,
        client_id: client_id
      }
    )

    conn
    |> store_user_session(session_token)
    |> put_session(:session_chosen, true)
    |> redirect(to: after_sign_in_path(conn))
  end

  @impl BorutaIdentity.Accounts.SessionApplication
  def authentication_failure(%Plug.Conn{} = conn, %SessionError{
        message: message,
        template: template
      }) do
    client_id = client_id_from_request(conn)

    :telemetry.execute(
      [:authentication, :log_in, :failure],
      %{},
      %{
        message: message,
        client_id: client_id
      }
    )
    conn
    |> put_layout(false)
    |> put_status(:unauthorized)
    |> put_view(TemplateView)
    |> render("template.html",
      template: template,
      assigns: %{
        errors: [message]
      }
    )
  end

  @impl BorutaIdentity.Accounts.SessionApplication
  def session_deleted(conn) do
    client_id = client_id_from_request(conn)
    user = conn.assigns[:current_user]

    :telemetry.execute(
      [:authentication, :log_out, :success],
      %{},
      %{
        sub: user && user.uid,
        backend: user && user.backend,
        client_id: client_id
      }
    )

    conn
    |> remove_user_session()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: after_sign_out_path(conn))
  end
end
