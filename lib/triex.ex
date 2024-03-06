defmodule Triex do
  @moduledoc "The Triex trie interface."

  alias Triex.Node

  # ---------
  # constants
  # ---------

  @timeout 5 * 1_000

  # -----
  # types 
  # -----

  @type trie() :: {:trie, root :: pid()}
  defguard is_trie(t)
           when is_tuple(t) and tuple_size(t) == 2 and elem(t, 0) == :trie and is_pid(elem(t, 1))

  # types for tree info returned by 'dump'
  # 'node' is a reserved type, so use vert instead

  @type vert() :: {String.t(), :initial | :normal | :final}
  @type verts() :: [vert()]

  @type edge() :: {String.t(), String.t()}
  @type edges() :: [edge()]

  @type tree() :: {verts(), edges()}

  # -----------
  # constructor 
  # -----------

  @doc "Create a new empty trie."
  @spec new() :: trie()
  def new(), do: {:trie, Node.start(false)}

  @doc "Create a new trie with a set of strings."
  @spec new([String.t(), ...]) :: trie()
  def new(strs) do
    trie = new()
    add(trie, strs)
    trie
  end

  # ----------------
  # public functions
  # ----------------

  @doc """
  Blocking function to add one or more strings to the trie.

  Note that the function works through side-effects 
  creating new processes. It does not return a new trie,
  so no need to pipeline additions. The original trie is valid.
  """
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
    Enum.each(strs, &add(trie, &1))
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

  @doc """
  Blocking function to gather structural info from the trie.
  """
  @spec dump(trie()) :: tree()
  def dump(trie) when is_trie(trie) do
    dispatch(trie, {:dump, ""})
    dump_recv(1, [], [])
  end

  # -----------------
  # private functions
  # -----------------

  # receive dump messages with node and edge data
  # the count of nodes yet to report starts at 1
  # each node report decrements the count by one
  # but each outgoing edge increments the count by 1
  @spec dump_recv(non_neg_integer(), verts(), edges()) :: tree()

  defp dump_recv(0, nodes, edges), do: {Enum.sort(nodes), Enum.sort(edges)}

  defp dump_recv(n, nodes, edges) do
    receive do
      {:node, str, final?, chars} ->
        type =
          cond do
            final? -> :final
            str == "" -> :initial
            true -> :normal
          end

        new_nodes = [{str, type} | nodes]

        new_edges =
          Enum.reduce(chars, edges, fn c, es ->
            [{str, <<str::binary, c::utf8>>} | es]
          end)

        dump_recv(n - 1 + length(chars), new_nodes, new_edges)
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # send a message to the root node
  @spec dispatch(trie(), any()) :: any()
  defp dispatch({:trie, root}, payload), do: send(root, {self(), payload})
end
