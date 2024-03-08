defmodule Triex do
  @moduledoc "The Triex trie interface."
  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Std.Mol
  alias Exa.Std.Mol, as: M

  alias Exa.Gfx.Color.Col3f

  alias Exa.Dot.DotWriter, as: DOT
  alias Exa.Dot.Render

  alias Triex.Node

  # ---------
  # constants
  # ---------

  @timeout 5 * 1_000

  @root "_root_"

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
    # could sort strings by length here
    add(trie, strs)
    trie
  end

  # ----------------
  # public functions
  # ----------------

  @doc """
  Add one or more strings to the trie (serialized, blocking).

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

  @doc "Test a complete match of a single string in the trie (blocking)."
  @spec match(trie(), String.t()) :: bool()
  def match(trie, str) when is_trie(trie) do
    dispatch(trie, {:match, str})

    receive do
      {:matched, result} -> result
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @doc """
  Test multiple words for a complete match in the trie (parallel).

  The input strings are paired with an opaque application reference,
  which will be returned with the string in the result.
  The reference is typically a location in the text source, 
  such as:
  - character number `n`
  - `{line, column}`
  - `{filename, line, column}`
  """
  @spec matches(trie(), [{String.t(), any()}]) :: M.mol()
  def matches(trie, strefs) when is_trie(trie) and is_list(strefs) do
    self = self()

    Enum.each(strefs, fn {str, _ref} = stref ->
      Process.spawn(fn -> send(self, {stref, match(trie, str)}) end, [])
    end)

    match_recv(length(strefs), Mol.new())
  end

  defp match_recv(0, mol), do: Mol.reverse(mol)

  defp match_recv(n, mol) do
    receive do
      {_stref, false} -> match_recv(n - 1, mol)
      {{str, ref}, true} -> match_recv(n - 1, Mol.add(mol, str, ref))
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @doc "Match all tokens in a file against the trie."
  @spec match_file(trie(), E.filename()) :: any()
  def match_file(trie, filename) when is_filename(filename) do
    lines = Exa.File.from_file_lines(filename)
    IO.inspect(length(lines), label: "no. lines")

    # TODO - full file tokenization *****
    toks =
      lines
      |> hd()
      |> String.split(~r{[[:space:],.;:']+}, trim: true)
      |> Enum.map(&String.downcase/1)

    tokrefs = Enum.zip(toks, 1..length(toks))
    matches(trie, tokrefs)
  end

  @doc """
  Gather structural info from the trie (blocking, parallelized).
  """
  @spec dump(trie()) :: tree()
  def dump(trie) when is_trie(trie) do
    dispatch(trie, {:dump, ""})
    dump_recv(1, [], [])
  end

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
            [{str, <<c::utf8>>} | es]
          end)

        dump_recv(n - 1 + length(chars), new_nodes, new_edges)
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @doc """
  Gather structural info from the trie,
  convert to GraphViz DOT format and 
  optionally render as PNG 
  (if GraphViz is installed).
  """
  @spec dump_dot(trie(), E.filename(), bool()) :: String.t()
  def dump_dot(trie, filename, render? \\ true) when is_trie(trie) and is_filename(filename) do
    {nodes, edges} = dump(trie)

    ncol = Col3f.gray(0.1)
    ecol = Col3f.gray(0.2)

    dot = "trie"
    |> DOT.new_dot()
    |> DOT.reduce(nodes, fn
      {"", :initial}, dot -> DOT.node(dot, @root, color: ncol, shape: :point)
      {name, :normal}, dot -> DOT.node(dot, name, color: ncol, shape: :ellipse)
      {name, :final}, dot -> DOT.node(dot, name, color: ncol, shape: :doublecircle)
    end)
    |> DOT.reduce(edges, fn
      {"", label}, dot -> DOT.edge(dot, @root, label, color: ecol, label: label)
      {src, label}, dot -> DOT.edge(dot, src, src <> label, color: ecol, label: label)
    end)
    |> DOT.end_dot()
    |> DOT.to_file(filename)
    |> to_string()

    if render? do
      Render.render_dot(filename, :png)
    end

    dot
  end

  # -----------------
  # private functions
  # -----------------

  # send a message to the root node
  @spec dispatch(trie(), any()) :: any()
  defp dispatch({:trie, root}, payload), do: send(root, {self(), payload})
end
