defmodule BorutaWeb.Integration.OauthTest do
  use BorutaWeb.ConnCase, async: true

  import Boruta.Factory
  import BorutaIdentity.AccountsFixtures

  alias Boruta.Ecto.Token
  alias BorutaIdentity.Accounts

  setup %{conn: conn} do
    {:ok, conn: conn}
  end

  describe "#authorize" do
    setup %{conn: conn} do
      resource_owner = user_fixture()
      redirect_uri = "http://redirect.uri"
      client = insert(:client, redirect_uris: [redirect_uri])

      {:ok,
       conn: conn, client: client, redirect_uri: redirect_uri, resource_owner: resource_owner}
    end

    test "stores oauth request params in session when current_user is not set", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri
    } do
      oauth_url =
        Routes.authorize_path(conn, :authorize, %{
          response_type: "token",
          client_id: client.id,
          redirect_uri: redirect_uri,
          request: "request",
          code_challenge: "code challenge",
          state: "state",
          scope: "scope",
          nonce: "nonce"
        })

      conn = get(conn, oauth_url)

      assert get_session(conn, :user_return_to) |> URI.parse() == URI.parse(oauth_url)
    end

    test "redirects to choose session if session not chosen", %{
      conn: conn,
      redirect_uri: redirect_uri,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: "6a2f41a3-c54c-fce8-32d2-0324e1c32e22",
            redirect_uri: redirect_uri,
            state: "state"
          })
        )

      assert redirected_to(conn) == Routes.choose_session_path(conn, :new)
    end
  end

  describe "OpenID Connect" do
    setup %{conn: conn} do
      resource_owner = user_fixture()
      redirect_uri = "http://redirect.uri"
      client = insert(:client, redirect_uris: [redirect_uri])
      scope = insert(:scope, public: true)

      {:ok,
       conn: conn,
       client: client,
       redirect_uri: redirect_uri,
       resource_owner: resource_owner,
       scope: scope}
    end

    test "redirect to login with prompt='login'", %{conn: conn} do
      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            prompt: "login"
          })
        )

      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "redirects to login with prompt='none' without any current_user", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri
    } do
      conn = init_test_session(conn, session_chosen: true)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "id_token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            prompt: "none",
            scope: "openid",
            nonce: "nonce"
          })
        )

    assert redirected_to(conn) =~ ~r/error=login_required/
  end

    test "authorize with prompt='none' and a current_user", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner,
      redirect_uri: redirect_uri
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "id_token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            prompt: "none",
            scope: "openid",
            nonce: "nonce"
          })
        )

      assert url = redirected_to(conn)
      assert [_, _id_token] =
               Regex.run(
                 ~r/#{redirect_uri}#id_token=(.+)/,
                 url
               )
    end

    test "logs in with an expired max_age and current_user", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner,
      redirect_uri: redirect_uri
    } do
      conn =
        conn
        |> log_in(resource_owner)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "id_token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            scope: "openid",
            nonce: "nonce",
            max_age: 0
          })
        )

      assert redirected_to(conn) =~ ~r/log_in/
    end

    test "redirects to choose session with a non expired max_age and current_user", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner,
      redirect_uri: redirect_uri
    } do
      conn =
        conn
        |> log_in(resource_owner)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "id_token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            scope: "openid",
            nonce: "nonce",
            max_age: 10
          })
        )

      assert redirected_to(conn) =~ ~r/choose/
    end
  end

  describe "client_credentials grant" do
    setup %{conn: conn} do
      client = insert(:client)

      {:ok,
       conn: put_req_header(conn, "content-type", "application/x-www-form-urlencoded"),
       client: client}
    end

    test "returns an error with invalid query parameters", %{conn: conn} do
      conn = post(conn, "/oauth/token")

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request is not a valid OAuth request. Need a grant_type param."
             }
    end

    test "returns an error with an invalid grant type", %{conn: conn} do
      conn = post(conn, "/oauth/token", "grant_type=bad_grant_type")

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request body validation failed. #/grant_type do match required pattern /^(client_credentials|password|authorization_code|refresh_token)$/."
             }
    end

    test "returns an error with invalid body parameters", %{conn: conn} do
      conn = post(conn, "/oauth/token", "grant_type=client_credentials")

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request body validation failed. Required properties client_id, client_secret are missing at #."
             }
    end

    test "returns an error with invalid client_id", %{conn: conn} do
      conn =
        post(
          conn,
          "/oauth/token",
          "grant_type=client_credentials&client_id=666&client_secret=666"
        )

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request body validation failed. #/client_id do match required pattern /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/."
             }
    end

    test "returns an error with invalid client_id/secret couple", %{conn: conn} do
      conn =
        post(
          conn,
          "/oauth/token",
          "grant_type=client_credentials&client_id=6a2f41a3-c54c-fce8-32d2-0324e1c32e22&client_secret=666"
        )

      assert json_response(conn, 401) == %{
               "error" => "invalid_client",
               "error_description" => "Invalid client_id or client_secret."
             }
    end

    test "returns an error with invalid client_secret", %{conn: conn, client: client} do
      conn =
        post(
          conn,
          "/oauth/token",
          "grant_type=client_credentials&client_id=#{client.id}&client_secret=666"
        )

      assert json_response(conn, 401) == %{
               "error" => "invalid_client",
               "error_description" => "Invalid client_id or client_secret."
             }
    end

    test "returns a token response with valid client_id/client_secret", %{
      conn: conn,
      client: client
    } do
      conn =
        post(
          conn,
          "/oauth/token",
          "grant_type=client_credentials&client_id=#{client.id}&client_secret=#{client.secret}"
        )

      %{
        "access_token" => access_token,
        "token_type" => token_type,
        "expires_in" => expires_in,
        "refresh_token" => refresh_token
      } = json_response(conn, 200)

      assert access_token
      assert token_type == "bearer"
      assert expires_in
      assert refresh_token
    end
  end

  describe "implicit grant" do
    setup %{conn: conn} do
      resource_owner = user_fixture()
      redirect_uri = "http://redirect.uri"
      client = insert(:client, redirect_uris: [redirect_uri])
      scope = insert(:scope, public: true)

      {:ok,
       conn: conn,
       client: client,
       redirect_uri: redirect_uri,
       resource_owner: resource_owner,
       scope: scope}
    end

    # TODO test different validation cases
    test "validates request params", %{
      conn: conn,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      conn = get(conn, "/oauth/authorize")

      assert response_content_type(conn, :html)

      assert response(conn, 400) =~
               "Request is not a valid OAuth request. Need a response_type param."
    end

    test "returns an error if client_id is invalid", %{
      conn: conn,
      redirect_uri: redirect_uri,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: "6a2f41a3-c54c-fce8-32d2-0324e1c32e22",
            redirect_uri: redirect_uri,
            state: "state"
          })
        )

      assert html_response(conn, 401) =~ ~r/Invalid client_id or redirect_uri./
    end

    test "redirect to user authentication page", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri
    } do
      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: client.id,
            redirect_uri: redirect_uri
          })
        )

      # NOTE Path will be scoped in production with configuration and be forwarded to
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "redirects to redirect_uri with token if current_user is set", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: client.id,
            redirect_uri: redirect_uri
          })
        )

      [_, access_token, expires_in] =
        Regex.run(
          ~r/#{redirect_uri}#access_token=(.+)&expires_in=(.+)/,
          redirected_to(conn)
        )

      assert access_token
      assert expires_in
    end

    test "redirects to redirect_uri with state", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      given_state = "state"

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            state: given_state
          })
        )

      [_, access_token, expires_in, state] =
        Regex.run(
          ~r/#{redirect_uri}#access_token=(.+)&expires_in=(.+)&state=(.+)&token_type=bearer/,
          redirected_to(conn)
        )

      assert access_token
      assert expires_in
      assert state == given_state
    end

    test "renders preauthorize with scope", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri,
      resource_owner: resource_owner,
      scope: scope
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            scope: scope.name
          })
        )

      assert html_response(conn, 200) =~ ~r/#{scope.name}/
      assert html_response(conn, 200) =~ ~r/Consent/
    end

    test "redirects to redirect_uri with consented scope", %{
      conn: conn,
      client: client,
      redirect_uri: redirect_uri,
      resource_owner: resource_owner,
      scope: scope
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      Accounts.consent(resource_owner, %{client_id: client.id, scopes: [scope.name]})

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "token",
            client_id: client.id,
            redirect_uri: redirect_uri,
            scope: scope.name
          })
        )

      [_, access_token, expires_in] =
        Regex.run(
          ~r/#{redirect_uri}#access_token=(.+)&expires_in=(.+)/,
          redirected_to(conn)
        )

      assert access_token
      assert expires_in
    end
  end

  describe "password grant" do
    setup %{conn: conn} do
      password = valid_user_password()
      resource_owner = user_fixture(password: password)
      client = insert(:client)

      {:ok,
       conn: put_req_header(conn, "content-type", "application/x-www-form-urlencoded"),
       client: client,
       resource_owner: resource_owner,
       password: password}
    end

    test "returns a token response with valid client_id/client_secret", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner,
      password: password
    } do
      conn =
        post(
          conn,
          "/oauth/token",
          "grant_type=password&username=#{resource_owner.email}&password=#{password}&client_id=#{client.id}&client_secret=#{client.secret}"
        )

      %{
        "access_token" => access_token,
        "token_type" => token_type,
        "expires_in" => expires_in,
        "refresh_token" => refresh_token
      } = json_response(conn, 200)

      assert access_token
      assert token_type == "bearer"
      assert expires_in
      assert refresh_token
    end
  end

  describe "authorization code grant" do
    # TODO est token delivrance with code
    setup %{conn: conn} do
      resource_owner = user_fixture()
      client = insert(:client)
      scope = insert(:scope, public: true)

      {:ok,
       conn: put_req_header(conn, "content-type", "application/x-www-form-urlencoded"),
       client: client,
       resource_owner: resource_owner,
       scope: scope}
    end

    test "redirects to redirect_uri with errors in query if redirect_uri is invalid", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "code",
            client_id: client.id,
            redirect_uri: "http://bad.redirect.uri",
            state: "state"
          })
        )

      assert html_response(conn, 401) =~ ~r/Invalid client_id or redirect_uri./
    end

    test "redirects to redirect_uri with token if current_user is set", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      redirect_uri = List.first(client.redirect_uris)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "code",
            client_id: client.id,
            redirect_uri: redirect_uri
          })
        )

      [_, code] =
        Regex.run(
          ~r/#{redirect_uri}\?code=(.+)/,
          redirected_to(conn)
        )

      assert code
    end

    test "redirects to redirect_uri with state when session chosen", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      given_state = "state"
      redirect_uri = List.first(client.redirect_uris)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "code",
            client_id: client.id,
            redirect_uri: redirect_uri,
            state: given_state
          })
        )

      [_, code, state] =
        Regex.run(
          ~r/#{redirect_uri}\?code=(.+)&state=(.+)/,
          redirected_to(conn)
        )

      assert code
      assert state == given_state
    end

    test "renders preauthorize with scope", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner,
      scope: scope
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      redirect_uri = List.first(client.redirect_uris)

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "code",
            client_id: client.id,
            redirect_uri: redirect_uri,
            scope: scope.name
          })
        )

      assert html_response(conn, 200) =~ ~r/#{scope.name}/
      assert html_response(conn, 200) =~ ~r/Consent/
    end

    test "redirects to redirect_uri with consented scope", %{
      conn: conn,
      client: client,
      resource_owner: resource_owner,
      scope: scope
    } do
      conn =
        conn
        |> log_in(resource_owner)
        |> init_test_session(session_chosen: true)

      redirect_uri = List.first(client.redirect_uris)
      Accounts.consent(resource_owner, %{client_id: client.id, scopes: [scope.name]})

      conn =
        get(
          conn,
          Routes.authorize_path(conn, :authorize, %{
            response_type: "code",
            client_id: client.id,
            redirect_uri: redirect_uri,
            scope: scope.name
          })
        )

      [_, code] =
        Regex.run(
          ~r/#{redirect_uri}\?code=(.+)/,
          redirected_to(conn)
        )

      assert code
    end
  end

  describe "introspect" do
    setup %{conn: conn} do
      client = insert(:client)
      client_token = insert(:token, type: "access_token", client: client)
      resource_owner = user_fixture()

      resource_owner_token =
        insert(:token, type: "access_token", value: "888", client: client, sub: resource_owner.id)

      {:ok,
       conn: put_req_header(conn, "content-type", "application/x-www-form-urlencoded"),
       client: client,
       client_token: client_token,
       resource_owner_token: resource_owner_token,
       resource_owner: resource_owner}
    end

    test "returns an error if request is invalid", %{conn: conn} do
      conn =
        post(
          conn,
          "/oauth/introspect"
        )

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request validation failed. Required properties client_id, client_secret, token are missing at #."
             }
    end

    test "returns an error if client is invalid", %{conn: conn, client: client} do
      conn =
        post(
          conn,
          "/oauth/introspect",
          "client_id=#{client.id}&client_secret=bad_secret&token=token"
        )

      assert json_response(conn, 401) == %{
               "error" => "invalid_client",
               "error_description" => "Invalid client_id or client_secret."
             }
    end

    test "returns an inactive token response if token is invalid", %{conn: conn, client: client} do
      conn =
        post(
          conn,
          "/oauth/introspect",
          "client_id=#{client.id}&client_secret=#{client.secret}&token=bad_token"
        )

      assert json_response(conn, 200) == %{"active" => false}
    end

    test "returns an introspect token response if client, token are valid", %{
      conn: conn,
      client: client,
      client_token: token
    } do
      conn =
        post(
          conn,
          "/oauth/introspect",
          "client_id=#{client.id}&client_secret=#{client.secret}&token=#{token.value}"
        )

      assert json_response(conn, 200) == %{
               "active" => true,
               "client_id" => client.id,
               "exp" => token.expires_at,
               "iat" => DateTime.to_unix(token.inserted_at),
               "iss" => "boruta",
               "scope" => token.scope,
               "sub" => nil,
               "username" => nil
             }
    end

    test "returns an introspect token response if resource owner token is valid", %{
      conn: conn,
      client: client,
      resource_owner_token: token,
      resource_owner: resource_owner
    } do
      conn =
        post(
          conn,
          "/oauth/introspect",
          "client_id=#{client.id}&client_secret=#{client.secret}&token=#{token.value}"
        )

      assert json_response(conn, 200) == %{
               "active" => true,
               "client_id" => client.id,
               "exp" => token.expires_at,
               "iat" => DateTime.to_unix(token.inserted_at),
               "iss" => "boruta",
               "scope" => token.scope,
               "sub" => resource_owner.id,
               "username" => resource_owner.email
             }
    end

    test "returns a jwt token when accept header set", %{
      conn: conn,
      client: client,
      client_token: token
    } do
      signer = Joken.Signer.create("RS512", %{"pem" => client.public_key})
      conn = put_req_header(conn, "accept", "application/jwt")

      conn =
        post(
          conn,
          "/oauth/introspect",
          "client_id=#{client.id}&client_secret=#{client.secret}&token=#{token.value}"
        )

      case Joken.Signer.verify(response(conn, 200), signer) do
        {:ok, payload} ->
          assert payload == %{
                   "active" => true,
                   "client_id" => client.id,
                   "exp" => token.expires_at,
                   "iat" => DateTime.to_unix(token.inserted_at),
                   "iss" => "boruta",
                   "scope" => token.scope,
                   "sub" => nil,
                   "username" => nil
                 }

        _ ->
          assert false
      end
    end
  end

  describe "revoke" do
    setup %{conn: conn} do
      client = insert(:client)
      client_token = insert(:token, type: "access_token", value: "777", client: client)
      resource_owner = user_fixture()

      resource_owner_token =
        insert(:token, type: "access_token", value: "888", client: client, sub: resource_owner.id)

      {:ok,
       conn: put_req_header(conn, "content-type", "application/x-www-form-urlencoded"),
       client: client,
       client_token: client_token,
       resource_owner_token: resource_owner_token,
       resource_owner: resource_owner}
    end

    test "returns an error if request is invalid", %{conn: conn} do
      conn =
        post(
          conn,
          "/oauth/revoke"
        )

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request validation failed. Required properties client_id, client_secret, token are missing at #."
             }
    end

    test "returns an error if client is invalid", %{conn: conn, client: client} do
      conn =
        post(
          conn,
          "/oauth/revoke",
          "client_id=#{client.id}&client_secret=bad_secret&token=token"
        )

      assert json_response(conn, 401) == %{
               "error" => "invalid_client",
               "error_description" => "Invalid client_id or client_secret."
             }
    end

    test "returns a success if token is invalid", %{conn: conn, client: client} do
      conn =
        post(
          conn,
          "/oauth/revoke",
          "client_id=#{client.id}&client_secret=#{client.secret}&token=bad_token"
        )

      assert response(conn, 200)
    end

    test "return a success if client, token are valid", %{
      conn: conn,
      client: client,
      client_token: token
    } do
      conn =
        post(
          conn,
          "/oauth/revoke",
          "client_id=#{client.id}&client_secret=#{client.secret}&token=#{token.value}"
        )

      assert response(conn, 200)
    end

    test "revoke token if client, token are valid", %{
      conn: conn,
      client: client,
      client_token: token
    } do
      post(
        conn,
        "/oauth/revoke",
        "client_id=#{client.id}&client_secret=#{client.secret}&token=#{token.value}"
      )

      assert BorutaWeb.Repo.get_by(Token, value: token.value).revoked_at
    end
  end
end
