defmodule Plaid.Client do
  @moduledoc """
  Functions to build a Tesla client for handling HTTP requests.
  """

  defmodule Request do
    @moduledoc """
    Data structure for an HTTP request with convenience functions.
    """

    defstruct body: nil, endpoint: nil, method: nil, opts: %{}
    @type t :: %__MODULE__{body: map, endpoint: String.t(), method: atom, opts: map}

    @spec to_options(Request.t()) :: keyword
    def to_options(%Request{body: b, endpoint: e, method: m, opts: o}) do
      [method: m, url: e, body: b, opts: Map.to_list(o)]
    end

    @spec put_metadata(Request.t(), map) :: Request.t()
    def put_metadata(%Request{endpoint: e, method: m, opts: o} = request, config) do
      metadata =
        Map.new()
        |> Map.put(:method, m)
        |> Map.put(:path, e)
        |> Map.put(:u, :native)
        |> Map.merge(config[:telemetry_metadata] || %{})

      %{request | opts: Map.put(o, :metadata, metadata)}
    end
  end

  @spec new(map) :: Tesla.Client.t()
  def new(config \\ %{}) do
    middleware = [
      {Tesla.Middleware.BaseUrl, get_base_url(config)},
      {Tesla.Middleware.Headers,
       [
         {"Content-Type", "application/json"},
         {"user-agent", "Elixir-SDK"},
         {"Plaid-Version", "2020-09-14"},
         {"PLAID-CLIENT-ID", get_client_id(config)},
         {"PLAID-SECRET", get_secret(config)}
       ]},
      Tesla.Middleware.JSON,
      Plaid.Telemetry
    ]

    adapter = {get_adapter(config), get_http_options(config)}

    Tesla.client(middleware, adapter)
  end

  defp get_base_url(config) do
    case config[:root_uri] || Application.get_env(:plaid, :root_uri) do
      nil ->
        raise Plaid.MissingRootUriError

      root_uri ->
        root_uri
    end
  end

  defp get_client_id(config) do
    case config[:client_id] || Application.get_env(:plaid, :client_id) do
      nil ->
        raise Plaid.MissingClientIdError

      client_id ->
        client_id
    end
  end

  defp get_secret(config) do
    case config[:secret] || Application.get_env(:plaid, :secret) do
      nil ->
        raise Plaid.MissingSecretError

      secret ->
        secret
    end
  end

  defp get_adapter(config) do
    config[:adapter] || Application.get_env(:plaid, :adapter) || Tesla.Adapter.Hackney
  end

  defp get_http_options(config) do
    Keyword.merge(
      Application.get_env(:plaid, :http_options, []),
      config[:http_options] || []
    )
  end
end
