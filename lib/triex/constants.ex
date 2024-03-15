defmodule Triex.Constants do
  @moduledoc "Constants for Triex."

  defmacro __using__(_) do
    quote do
      # backstop timeout for all receives in asynch execution
      @timeout 5 * 1_000
    end
  end
end
