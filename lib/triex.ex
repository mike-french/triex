defmodule Triex do
  @moduledoc "The Triex trie interface."

  alias Triex.Node

  # -----
  # types 
  # -----

  @type trie() :: {:trie, root :: pid()}
  defguard is_trie(t) when 
    is_tuple(t) and tuple_size(t) == 2 and elem(t,0) == :trie and is_pid(elem(t,1))

  @timeout 5 * 1_000

  # -----------
  # constructor 
  # -----------

  @doc "Create a new trie."
  @spec new() :: trie()
  def new(), do: {:trie, Node.start(false)}

  # ----------------
  # public functions
  # ----------------

  @doc "Blocking function to add one or more strings to the trie."
  @spec add(trie(), String.t() | [String.t(), ...]) :: :ok

  def add(trie, str) when is_trie(trie) and is_binary(str) do
    dispatch(trie, {:add, str})

    receive do
      {:add, :ok} -> :ok
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  def add(trie, strs) when is_trie(trie) and is_list(strs) do
    Enum.each(strs, & add(trie,&1))
  end

  @doc "Blocking function to match a string in the trie."
  @spec match(trie(), String.t()) :: bool()
  def match(trie, str) when is_trie(trie) do
    dispatch(trie, {:match, str})

    receive do
      {:result, result} -> result
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # -----------------
  # private functions
  # -----------------

  # send a message to the root node
  @spec dispatch(trie(), any()) :: any()
  defp dispatch({:trie, root}, payload), do: send(root, {self(), payload})
end
