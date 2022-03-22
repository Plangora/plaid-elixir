# Plaid

[![Build Status](https://travis-ci.org/wfgilman/plaid-elixir.svg?branch=master)](https://travis-ci.org/wfgilman/plaid-elixir)
[![Coverage Status](https://coveralls.io/repos/github/wfgilman/plaid-elixir/badge.svg?branch=master)](https://coveralls.io/github/wfgilman/plaid-elixir?branch=master)
[![Module Version](https://img.shields.io/hexpm/v/plaid_elixir.svg)](https://hex.pm/packages/plaid_elixir)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/plaid_elixir/)
[![Total Download](https://img.shields.io/hexpm/dt/plaid_elixir.svg)](https://hex.pm/packages/plaid_elixir)
[![License](https://img.shields.io/hexpm/l/plaid_elixir.svg)](https://github.com/wfgilman/plaid-elixir/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/wfgilman/plaid-elixir.svg)](https://github.com/wfgilman/plaid-elixir/commits/master)

Elixir library for Plaid's V2 API.

Supported Plaid products:

- [x] Transactions
- [x] Auth
- [x] Identity
- [x] Balance
- [x] Income
- [ ] Assets
- [x] Investments

[Plaid Documentation](https://plaid.com/docs/api)

## Changes in 3.0

`3.0` replaces [HTTPoison](https://github.com/edgurgel/httpoison) with [Tesla](https://github.com/teamon/tesla)
behind the scenes to provide more flexibility around HTTP calls. Additionally, `3.0` refactors
the test suite, hard deprecates several functions, and fixes small bugs when decoding Plaid JSON
responses into internal data structures.

While these changes are primarily transparent, if you are considering upgrading to version `3.0`
it's recommended you review the full list of breaking changes in the changelog.

## Usage

Add to your dependencies in `mix.exs`. The hex specification is required.

```elixir
def deps do
  [
    {:plaid, "~> 3.0", hex: :plaid_elixir}
  ]
end
```

## Configuration

All calls to Plaid require your client id and secret. Add the following configuration
to your project to set the values. This configuration is optional, see below for a
runtime configuration. The library will raise an error if the relevant credentials
are not provided either via `config.exs` or at runtime.

```elixir
config :plaid,
  root_uri: "https://development.plaid.com/",
  client_id: "your_client_id",
  secret: "your_secret",
  http_client: Plaid.HTTPClient, # optional
  http_options: [timeout: 10_000, recv_timeout: 30_000] # optional
```

By default, `root_uri` is set by `mix` environment. You can override it in your config.
- `dev` - development.plaid.com
- `prod` - production.plaid.com

Finally, you can specify your HTTP client of choice with `http_client` in a module that implements the
`Plaid.HTTPClient.call/6` behaviour. Under the hood, the HTTP client implementation uses [Tesla](https://github.com/teamon/tesla)
for middleware and [hackney](https://github.com/benoitc/hackney) as the actual HTTP client adapter, which
is the HTTP client used by prior versions of this library. If this no value is provided, the library
will use the default implementation, `Plaid.HTTPClient`.

The `http_options` key specifies the custom configuration for HTTP client adapter. It's recommended you
extend the receive timeout for Plaid, especially for retrieving historical transactions. In the code
snippet above, `[timeout: 10_000, recv_timeout: 30_000]` are timeout options understood by hackney.

## Runtime configuration

Alternatively, you can provide the configuration at runtime. The configuration passed
as a function argument will overwrite the configuration in `config.exs`, if one exists.

For example, if you want to hit a different URL when calling the `/accounts` endpoint, you could
pass in a configuration argument to `Plaid.Accounts.get/2`.

```elixir
Plaid.Accounts.get(
  %{access_token: "my-token"},
  %{root_uri: "http://sandbox.plaid.com/", secret: "no-secrets"}
)
```

HTTP client options may also be passed to the configuration at runtime. This can be
useful if you'd like to extend the `recv_timeout` parameter for certain calls to Plaid.

```elixir
Plaid.Transactions.get(
  %{access_token: "my-token"},
  %{http_options: [recv_timeout: 10_000]}
)
```

## Obtaining Access Tokens

Access tokens are required for almost all calls to Plaid. However, they can only be obtained
using [Plaid Link](https://plaid.com/docs/link/transition-guide/#creating-items-with-link).

Call the `/link` endpoint to create a link token that you'll use to initialize Plaid Link.
Once a user successfully connects to his institution using Plaid Link, a
public token is returned to the client. This single-use public token can be exchanged
for an access token and item id (both of which should be stored) using
`Plaid.Item.exchange_public_token/1`.

Consult Plaid's documentation for additional detail on this process.

## Metrics

This library emits [telemetry](https://github.com/beam-telemetry/telemetry) that you can use to get insight into communication
between your system and Plaid service. Emitted events are designed to be similar to the ones Phoenix emits. Those are the following:
* `[:plaid, :request, :start]` with `:system_time` measurement - signifies the moment request is being initiated
* `[:plaid, :request, :stop]` with `:duration` measurement - emitted after request has been finished
* `[:plaid, :request, :exception]` with `:duration` measurement - emitted in case there's an exception while making a request

Metadata attached (if applicable to event type) are as follows:
* `:method`, `:path`, `:status` - HTTP information on the request.
* `:u` - unit in which time is reported. Only value is `:native`.
* `:exception` - The exception that was thrown during making the request.
* `:result` - If no exception, contains either `{:ok, %Tesla.Env{}}` or `{:error, reason}`

Additionally, you can pass your custom metadata through the `config` parameter when calling a product endpoint.
Put it under `telemetry_metadata` and it will be merged to the standard metadata map.

All times are in `:native` unit. Telemetry instrumentation is implemented using [Tesla.Middleware](https://github.com/teamon/tesla#middleware).

## Custom Middleware

Using [Tesla](https://github.com/teamon/tesla) under the hood provides additional capabilities that can
be useful for communicating with Plaid, such as retry logic and logging, or emitting refined telemetry events.
To use customized middleware, perform the following steps.

### 1. Implement the Plaid.HTTPClient.call/6 behaviour
Add a new module to your project that conforms to the Plaid.HTTPClient behaviour, then specify it in `config.exs`.

```elixir
defmodule MyHTTPClient do

  @behaviour Plaid.HTTPClient

  @impl Plaid.HTTPClient
  def call(method, url, body, headers, http_options, metadata) do
    client = new(http_options)

    options = [
      method: method,
      url: url,
      headers: headers,
      body: body,
      opts: [metadata: metadata]
    ]

    case Tesla.request(client, options) do
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:ok, %Plaid.HTTPClient.Response{status_code: status, body: Poison.Parser.parse!(body, %{})}}

      {:error, reason} ->
        {:error, %Plaid.HTTPClient.Error{reason: reason}}
    end
  end

  defp new(http_options) do
    ...
  end
end
```

```elixir
config :plaid,
  http_client: MyHTTPClient
```

### 2. Create your custom Tesla client
Build a Tesla client with your desired HTTP adapter and Middlewares. Consult the Tesla [documentation](https://hexdocs.pm/tesla/readme.html) to see which middlewares require mix dependencies and inclusion in `application/0`.
```elixir
defmodule MyHTTPClient do

  @behaviour Plaid.HTTPClient

  @impl Plaid.HTTPClient
  def call(method, url, body, headers, http_options, metadata) do
    client = new(http_options)
    ...
  end

  defp new(http_options) do
    middleware = [
      Tesla.Middleware.JSON,
      Tesla.Middleware.Logger, # Custom logging
      Tesla.Middleware.Fuse,   # Custom retry
      MyMiddleware             # Custom middleware
    ]

    adapter = {Tesla.Adapter.Hackney, http_options}
    Tesla.client(middleware, adapter)
  end
end
```
```elixir
# mix.exs

def application do
  [extra_applications: [:logger, :fuse]]
end

defp deps do
  ...
  {:fuse, "~> 2.4"}
end
```

### 3. Write your custom Middlewares
If the standard middlewares available in the Tesla library do not meet your needs you can write your own. Just create a new module in your project which conforms to the [`Tesla.Middleware.call/3`](https://hexdocs.pm/tesla/Tesla.Middleware.html#c:call/3) behaviour and add it to the list of middlewares defined in your custom HTTP client.

```elixir
defmodule MyMiddleware do

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    ...
  end
end
```

## Compatibility

This library natively supports serialization of its structs using `Jason` for compatibility with Phoenix.

## Tests and Style

This library tries to implement best practices for unit and integration testing and
version `3.0` implements major improvements.

Unit testing is done using [mox](https://github.com/dashbitco/mox) and follows the principals
outlined in the well-known article by José Valim linked in that repo.  Unit tests can
be run standalone using `ExUnit` tags.
```
mix test --only unit
```

Integration testing uses [bypass](https://github.com/PSPDFKit-labs/bypass) to simulate HTTP responses from Plaid.
Integration tests can also be run in isolation using tags.
```
mix test --only integration
```

Static analysis is performed using [dialyzer](https://github.com/jeremyjh/dialyxir).

Elixir's native formatter is used along with [credo](https://github.com/rrrene/credo)
for code analysis.

## Copyright and License

Copyright (c) 2016 Will Gilman

This work is free. You can redistribute it and/or modify it under the
terms of the MIT License. See the [LICENSE.md](./LICENSE.md) file for more details.
