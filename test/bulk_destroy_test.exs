defmodule Repro.BulkDestroyTest do
  @moduledoc """
  On a temporal resource, an atomic bulk write fails with an SQL error when it
  returns records and the selected columns leave out the period attribute.

  A bulk destroy does that by default: with no `select`, it selects the public
  attributes, and the period attribute is private. A bulk update selects the
  attributes selected by default, which include it, so it only fails when given
  a `select` without it.
  """
  use ExUnit.Case, async: false

  require Ash.Query

  alias Repro.Blog.Post

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repro.Repo)
    post = Ash.create!(Post, %{title: "A"})
    %{post: post, query: Post |> Ash.Query.filter(id == ^post.id)}
  end

  defp gone?(id), do: Post |> Ash.Query.filter(id == ^id) |> Ash.read!() == []

  describe "atomic bulk destroy of a query" do
    test "with notify?: true", %{post: post, query: query} do
      result =
        Ash.bulk_destroy(query, :destroy, %{},
          strategy: [:atomic],
          notify?: true,
          return_errors?: true
        )

      assert %Ash.BulkResult{status: :success} = result
      assert gone?(post.id)
    end

    test "with return_records?: true", %{post: post, query: query} do
      result =
        Ash.bulk_destroy(query, :destroy, %{},
          strategy: [:atomic],
          return_records?: true,
          return_errors?: true
        )

      assert %Ash.BulkResult{status: :success, records: [%Post{}]} = result
      assert gone?(post.id)
    end
  end

  describe "the same error, from an atomic bulk update that selects no period column" do
    test "with notify?: true and select: [:id, :title]", %{query: query} do
      result =
        Ash.bulk_update(query, :update, %{title: "B"},
          strategy: [:atomic],
          notify?: true,
          return_errors?: true,
          select: [:id, :title]
        )

      assert %Ash.BulkResult{status: :success} = result
    end
  end

  describe "works" do
    test "atomic bulk destroy of a query, with notify?: true and select including :valid_at",
         %{post: post, query: query} do
      assert %Ash.BulkResult{status: :success} =
               Ash.bulk_destroy(query, :destroy, %{},
                 strategy: [:atomic],
                 notify?: true,
                 return_errors?: true,
                 select: [:id, :title, :valid_at]
               )

      assert gone?(post.id)
    end

    test "atomic bulk destroy of a query, returning nothing", %{post: post, query: query} do
      assert %Ash.BulkResult{status: :success} =
               Ash.bulk_destroy(query, :destroy, %{}, strategy: [:atomic], return_errors?: true)

      assert gone?(post.id)
    end

    test "streamed bulk destroy of a query, with notify?: true", %{post: post, query: query} do
      assert %Ash.BulkResult{status: :success} =
               Ash.bulk_destroy(query, :destroy, %{},
                 strategy: [:stream],
                 notify?: true,
                 return_errors?: true
               )

      assert gone?(post.id)
    end

    test "atomic bulk update of a query, with notify?: true and return_records?: true",
         %{query: query} do
      assert %Ash.BulkResult{status: :success, records: [%Post{title: "B"}]} =
               Ash.bulk_update(query, :update, %{title: "B"},
                 strategy: [:atomic],
                 notify?: true,
                 return_records?: true,
                 return_errors?: true
               )
    end

    test "destroying the record", %{post: post} do
      Post |> Ash.get!(post.id) |> Ash.destroy!()
      assert gone?(post.id)
    end
  end
end
