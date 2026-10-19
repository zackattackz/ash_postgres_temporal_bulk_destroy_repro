defmodule Repro.Blog do
  use Ash.Domain, otp_app: :repro

  resources do
    resource Repro.Blog.Post
  end
end
