defmodule Inngest.FnOpts do
  @moduledoc """
  Function configuration options
  """

  defstruct [
    :id,
    :name,
    :debounce,
    :batch_events,
    :rate_limit,
    :idempotency,
    :concurrency,
    retries: 3
  ]

  alias Inngest.Util

  @type t() :: %__MODULE__{
          id: binary(),
          name: binary(),
          retries: number() | nil,
          debounce: debounce() | nil,
          batch_events: batch_events() | nil,
          rate_limit: rate_limit() | nil,
          idempotency: idempotency() | nil,
          concurrency: concurrency() | nil
        }

  @type debounce() :: %{
          key: binary() | nil,
          period: binary()
        }

  @type batch_events() :: %{
          max_size: number(),
          timeout: binary()
        }

  @type rate_limit() :: %{
          limit: number(),
          period: binary(),
          key: binary() | nil
        }

  @type idempotency() :: binary()

  @type concurrency() ::
          number()
          | concurrency_option()
          | list(concurrency_option())

  @type concurrency_option() :: %{
          limit: number(),
          key: binary() | nil,
          scope: binary() | nil
        }
  @concurrency_scopes ["fn", "env", "account"]

  @doc """
  Validate the debounce configuration
  """
  @spec validate_debounce(t(), map()) :: map()
  def validate_debounce(fnopts, config) do
    case fnopts |> Map.get(:debounce) do
      nil ->
        config

      debounce ->
        period = Map.get(debounce, :period)

        if is_nil(period) do
          raise Inngest.DebounceConfigError, message: "'period' must be set for debounce"
        end

        case Util.parse_duration(period) do
          {:error, error} ->
            raise Inngest.DebounceConfigError, message: error

          {:ok, seconds} ->
            # credo:disable-for-next-line
            if seconds > 7 * Util.day_in_seconds() do
              raise Inngest.DebounceConfigError,
                message: "cannot specify period for more than 7 days"
            end
        end

        Map.put(config, :debounce, debounce)
    end
  end

  @doc """
  Validate the event batch config
  """
  @spec validate_batch_events(t(), map()) :: map()
  def validate_batch_events(fnopts, config) do
    case fnopts |> Map.get(:batch_events) do
      nil ->
        config

      batch ->
        max_size = Map.get(batch, :max_size)
        timeout = Map.get(batch, :timeout)

        if is_nil(max_size) || is_nil(timeout) do
          raise Inngest.BatchEventConfigError,
            message: "'max_size' and 'timeout' must be set for batch_events"
        end

        case Util.parse_duration(timeout) do
          {:error, error} ->
            raise Inngest.BatchEventConfigError, message: error

          {:ok, seconds} ->
            # credo:disable-for-next-line
            if seconds < 1 || seconds > 60 do
              raise Inngest.BatchEventConfigError,
                message: "'timeout' duration set to '#{timeout}', needs to be 1s - 60s"
            end
        end

        batch = %{maxSize: max_size, timeout: timeout}
        Map.put(config, :batchEvents, batch)
    end
  end

  @doc """
  Validate the rate limit config
  """
  @spec validate_rate_limit(t(), map()) :: map()
  def validate_rate_limit(fnopts, config) do
    case fnopts |> Map.get(:rate_limit) do
      nil ->
        config

      rate_limit ->
        limit = Map.get(rate_limit, :limit)
        period = Map.get(rate_limit, :period)

        if is_nil(limit) || is_nil(period) do
          raise Inngest.RateLimitConfigError,
            message: "'limit' and 'period' must be set for rate_limit"
        end

        case Util.parse_duration(period) do
          {:error, error} ->
            raise Inngest.RateLimitConfigError, message: error

          {:ok, seconds} ->
            # credo:disable-for-next-line
            if seconds < 1 || seconds > 60 do
              raise Inngest.RateLimitConfigError,
                message: "'period' duration set to '#{period}', needs to be 1s - 60s"
            end
        end

        Map.put(config, :rateLimit, rate_limit)
    end
  end

  @doc """
  Validate the concurrency config
  """
  @spec validate_concurrency(t(), map()) :: map()
  def validate_concurrency(fnopts, config) do
    case fnopts |> Map.get(:concurrency) do
      nil ->
        config

      %{} = setting ->
        validate_concurrency(setting)
        Map.put(config, :concurrency, setting)

      [_ | _] = settings ->
        Enum.each(settings, &validate_concurrency/1)
        Map.put(config, :concurrency, settings)

      setting ->
        if is_number(setting) do
          Map.put(config, :concurrency, setting)
        else
          raise Inngest.ConcurrencyConfigError, message: "invalid concurrency setting"
        end
    end
  end

  defp validate_concurrency(%{} = setting) do
    limit = Map.get(setting, :limit)
    scope = Map.get(setting, :scope)

    if is_nil(limit) do
      raise Inngest.ConcurrencyConfigError, message: "'limit' must be set for concurrency"
    end

    if !is_nil(scope) && !Enum.member?(@concurrency_scopes, scope) do
      raise Inngest.ConcurrencyConfigError,
        message: "invalid scope '#{scope}', needs to be \"fn\"|\"env\"|\"account\""
    end
  end
end
