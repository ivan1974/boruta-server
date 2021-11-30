defmodule BorutaIdentity.RelyingPartiesTest do
  use BorutaIdentity.DataCase

  alias BorutaIdentity.RelyingParties

  describe "relying_parties" do
    alias BorutaIdentity.RelyingParties.RelyingParty

    @valid_attrs %{name: "some name", type: "internal"}
    @update_attrs %{name: "some updated name"}
    @invalid_attrs %{name: nil, type: "other"}

    def relying_party_fixture(attrs \\ %{}) do
      {:ok, relying_party} =
        attrs
        |> Enum.into(@valid_attrs)
        |> RelyingParties.create_relying_party()

      relying_party
    end

    test "list_relying_parties/0 returns all relying_parties" do
      relying_party = relying_party_fixture()
      assert RelyingParties.list_relying_parties() == [relying_party]
    end

    test "get_relying_party!/1 returns the relying_party with given id" do
      relying_party = relying_party_fixture()
      assert RelyingParties.get_relying_party!(relying_party.id) == relying_party
    end

    test "create_relying_party/1 with valid data creates a relying_party" do
      assert {:ok, %RelyingParty{} = relying_party} =
               RelyingParties.create_relying_party(@valid_attrs)

      assert relying_party.name == "some name"
      assert relying_party.type == "internal"
    end

    test "create_relying_party/1 with invalid data returns error changeset" do
      assert {:error,
              %Ecto.Changeset{
                errors: [
                  type: {"is invalid", [validation: :inclusion, enum: ["internal"]]},
                  name: {"can't be blank", [validation: :required]}
                ]
              }} = RelyingParties.create_relying_party(@invalid_attrs)
    end

    test "update_relying_party/2 with valid data updates the relying_party" do
      relying_party = relying_party_fixture()

      assert {:ok, %RelyingParty{} = relying_party} =
               RelyingParties.update_relying_party(relying_party, @update_attrs)

      assert relying_party.name == "some updated name"
    end

    test "update_relying_party/2 with invalid data returns error changeset" do
      relying_party = relying_party_fixture()

      assert {:error, %Ecto.Changeset{}} =
               RelyingParties.update_relying_party(relying_party, @invalid_attrs)

      assert relying_party == RelyingParties.get_relying_party!(relying_party.id)
    end

    test "delete_relying_party/1 deletes the relying_party" do
      relying_party = relying_party_fixture()
      assert {:ok, %RelyingParty{}} = RelyingParties.delete_relying_party(relying_party)

      assert_raise Ecto.NoResultsError, fn ->
        RelyingParties.get_relying_party!(relying_party.id)
      end
    end

    test "change_relying_party/1 returns a relying_party changeset" do
      relying_party = relying_party_fixture()
      assert %Ecto.Changeset{} = RelyingParties.change_relying_party(relying_party)
    end
  end
end