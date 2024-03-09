defmodule Triex do
  @moduledoc "The Triex trie interface."
  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Std.Mol
  alias Exa.Std.Mol, as: M

  alias Exa.CharStream

  alias Exa.Gfx.Color.Col3f

  alias Exa.Dot.DotWriter, as: DOT
  alias Exa.Dot.Render

  alias Triex.Node

  # ---------
  # constants
  # ---------

  # backstop timeout for all receives in asynch execution
  @timeout 5 * 1_000

  # node id for the root in DOT output
  @root "_root_"

  # -----
  # types 
  # -----

  @type trie() :: {:trie, root :: pid()}
  defguard is_trie(t)
           when is_tuple(t) and tuple_size(t) == 2 and elem(t, 0) == :trie and is_pid(elem(t, 1))

  # types for tree info returned by 'dump'
  # 'node' is a reserved type, so use vert instead

  @typedoc """
  Node type for DOT graph output.
  The type determines the node representation in diagrams.

  There are three types:
  - initial means the virtual root, there is only 1
  - normal means any internal (non-leaf) node 
    that is not a member of the trie
    so traversals always continue
  - final means a node that is a member of the trie
    where traversals may terminate
    it includes some zero or more internal nodes and _all_ leaf nodes
  """
  @type vert_type() :: :initial | :normal | :final
  @type vert() :: {String.t(), vert_type()}
  @type verts() :: [vert()]

  @type edge() :: {String.t(), String.t()}
  @type edges() :: [edge()]

  @type tree() :: {verts(), edges()}

  defmodule Metrics do
    defstruct [:node, :edge, :head, :final, :branch, :leaf, root: 1]
  end

  @typedoc """
  Metrics for counts of trie structure:
  - _node:_ total number of nodes, including the root 
  - _edge:_ total number of edges
  - _root:_ the number of root nodes  
  - _head:_ number of edges leaving the root
  - _final:_ number of nodes that can return a successful result
  - _branch:_ number of nodes that have more than one outgoing edge
  - _leaf:_ number of nodes that do not have any outgoing edges
            
  The trie is a tree, so:
  - there is always exactly 1 root 
  - the number of edges is always one less 
    than the number of nodes
    (all nodes have exactly one parent node,
     except the root).

  The number of heads is equal to the number of 
  distinct starting letters of words in the trie.

  The number of final nodes is equal to 
  the number of words in the trie.

  Branches occur at the root 
  (empty string is a common prefix for all words)
  and when there are common prefixes within the trie.

  Leaves correspond to words that are not the prefix 
  of longer words in the trie - always final nodes.
  """
  @type metrics() :: %Metrics{
          node: E.count1(),
          edge: E.count(),
          head: E.count(),
          final: E.count(),
          branch: E.count(),
          leaf: E.count(),
          root: 1
        }

  # -----------
  # constructor 
  # -----------

  @doc "Create a new empty trie."
  @spec new() :: trie()
  def new(), do: {:trie, Node.start(false)}

  @doc """
  Create a new trie with a set of strings.

  It is assumed that the trie will not be further extended,
  so `add` will not be called after this constructor.
  """
  @spec new([String.t(), ...]) :: trie()
  def new(strs) do
    trie = new()
    # could sort strings by length here
    add(trie, strs)
    trie
  end

  # ---
  # add
  # ---

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

  # -----
  # match
  # -----

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
  - character number `nchar`
  - `{line, column, nchar}`
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

  defp match_recv(0, mol), do: Mol.sort(mol)

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
    toks = filename |> Exa.File.from_file_text() |> CharStream.tokenize()
    matches(trie, toks)
  end

  # ----
  # dump
  # ----

  @doc """
  Print structural info from the trie (blocking, parallelized).

  Returns the Metrics (see type definition).
  """
  @spec info(trie()) :: %Metrics{}
  def info({:trie, root} = trie) when is_pid(root) do
    {nodes, edges} = dump(trie)

    final =
      Enum.reduce(nodes, 0, fn
        {_, :final}, f -> f + 1
        _, f -> f
      end)

    histo = edges |> Enum.group_by(&elem(&1, 0)) |> Exa.Map.map(&length/1)

    histo =
      Enum.reduce(nodes, histo, fn
        {node, _}, h when is_map_key(h, node) -> h
        {node, _}, h -> Map.put(h, node, 0)
      end)

    otsih = Exa.Map.invert(histo) |> Exa.Map.map(&length/1)

    branch =
      Enum.reduce(otsih, 0, fn
        {nedge, count}, b when nedge > 1 -> b + count
        _, b -> b
      end)

    mx = %Metrics{
      node: length(nodes),
      edge: length(edges),
      head: Map.fetch!(histo, ""),
      final: final,
      branch: branch,
      leaf: Map.fetch!(otsih, 0)
    }

    IO.puts("Trie info:")
    IO.puts("  node:   #{mx.node}")
    IO.puts("  edge:   #{mx.edge}")
    IO.puts("  root:   #{mx.root}")
    IO.puts("  head:   #{mx.head}")
    IO.puts("  branch: #{mx.branch}")
    IO.puts("  final:  #{mx.final}")
    mx
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

    dot =
      "trie"
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
