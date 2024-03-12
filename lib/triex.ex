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

  @type trie() :: {:trie, root :: pid(), sink :: pid()}
  defguard is_trie(t)
           when is_tuple(t) and tuple_size(t) == 3 and elem(t, 0) == :trie and
                  is_pid(elem(t, 1)) and is_pid(elem(t, 2))

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
  @type vert_id() :: pos_integer()
  @type vert() :: {vert_id(), vert_label :: String.t(), vert_type()}
  @type verts() :: [vert()]

  @type edge() :: {src :: vert_id(), edge_label :: String.t(), dst :: vert_id()}
  @type edges() :: [edge()]

  @type tree() :: {verts(), edges()}

  # suffix map
  # constructed by add_revs and reverse
  # then used to construct the forward trie
  @typep sufmap() :: %{String.t() => pid()}

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

  @doc "Create a new trie with a set of target strings."
  @spec new([String.t(), ...]) :: trie()
  def new(strs) when is_list(strs) do
    trie = {:trie, Node.start(false), Node.start(true)}
    strs = Enum.sort_by(strs, &String.length/1, :desc)
    adds(trie, strs)
    trie
  end

  # @doc """
  # Create a new trie with a set of strings.

  # It is assumed that the trie will not be further extended,
  # so `add` will not be called after this constructor.
  # """
  # @spec new_rev([String.t(), ...]) :: trie()
  # def new_rev(strs) when is_list(strs) do
  #   trie = new()
  #   sufmap = add_revs(trie, strs)
  #   dispatch(trie, :reverse)

  #   Enum.each(sufmap, fn {suff, pid} ->
  #     IO.puts("")
  #     IO.puts(suff)
  #     t = {:trie, pid}
  #     info(t)
  #     tree = dump(t)
  #     IO.inspect(tree)
  #   end)
  #   trie = new()
  #   add_fors(trie, strs, sufmap)
  #   trie
  # end

  # ---
  # add
  # ---

  # Add one string to the reversed trie (blocking).
  # Return the address of the longest non-final suffix.
  # @spec add_rev(trie(), String.t()) :: :ignore | {String.t(), pid()}
  # defp add_rev(trie, str) when is_trie(trie) and is_binary(str) do
  #   dispatch(trie, {:add_rev, str, []})

  #   receive do
  #     {:add_rev, suf, pid} -> {suf, pid}
  #     {:add_rev, :ignore} -> :ignore
  #   after
  #     @timeout -> raise RuntimeError, message: "Timeout"
  #   end
  # end

  # Add a list of strings to the reversed trie (serialized, blocking).
  # Return the suffix map.
  # @spec add_revs(trie(), [String.t(), ...]) :: %{String.t() => pid()}
  # defp add_revs(trie, strs) when is_trie(trie) and is_list(strs) do
  #   # reverse each individual string
  #   # sorting shortest to longest makes longer extensions fail faster
  #   strs = strs 
  #   |> Enum.map(&String.reverse/1)
  #   |> Enum.sort_by(&String.length/1)
  #   # build the reverse trie for suffixes
  #   {sufmap, n} = Enum.reduce(strs, {%{},0}, fn str, {sufmap,n}=state -> 
  #     case add_rev(trie, str) do
  #       # note there can be repeated additions of the same suffix
  #       # when there is fanout to multiple final nodes
  #       # so final n will not necessarily be the same 
  #       # as the number of entries in the map
  #       {suf, pid} -> {Map.put(sufmap, suf, pid), n+1}
  #       :ignore -> state
  #     end      
  #   end)

  #   IO.inspect(sufmap, label: "sufmap")
  #   IO.inspect(n, label: "n")
  #   # --> insert dump here to see the reverse trie <--
  #   sufmap
  # end

  # ---
  # add
  # ---

  # Add one or more strings to the trie (serialized, blocking).
  @spec adds(trie(), [String.t(), ...]) :: :ok
  defp adds(trie, strs) when is_trie(trie) and is_list(strs) do
    Enum.each(strs, &add(trie, &1))
  end

  @spec add(trie(), String.t()) :: :ok
  defp add({:trie, _, sink} = trie, str) when is_trie(trie) and is_binary(str) do
    dispatch(trie, {:add, str, sink})

    receive do
      {:add, :ok} -> :ok
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # -----------
  # add forward 
  # -----------

  # @spec add_fors(trie(), [String.t(), ...], sufmap()) :: :ok
  # def add_fors(trie, strs, sufmap) when is_trie(trie) and is_list(strs) do
  #   # build the forward trie 
  #   Enum.each(strs, fn str ->       add_for(trie, str, sufmap)     end)
  # end

  # @spec add_for(trie(), String.t(), sufmap()) :: :ok
  # defp add_for(trie, str, sufmap) when is_trie(trie) and is_binary(str) do
  #   IO.inspect(str, label: "add_for")
  #   dispatch(trie, {:add_for, str, sufmap})
  #   receive do
  #     {:add_for, :ok} -> :ok
  #   after
  #     @timeout -> raise RuntimeError, message: "Timeout"
  #   end
  # end

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
  def info({:trie, root, _sink} = trie) when is_pid(root) do
    root_ipid = Exa.Process.ipid(root)
    {nodes, edges} = dump(trie)

    final =
      Enum.reduce(nodes, 0, fn
        {_, _, :final}, f -> f + 1
        _, f -> f
      end)

    # histogram for number of outgoing edges
    # the sink node with 0 out-edges will be missing
    histo =
      edges
      |> Enum.group_by(&elem(&1, 0))
      |> Exa.Map.map(&length/1)

    # find branches by inverting the histo gram 
    # and summing nodes with more than 1 out-edge
    branch =
      histo
      |> Exa.Map.invert()
      |> Exa.Map.map(&length/1)
      |> Enum.reduce(0, fn
        {nedge, count}, b when nedge > 1 -> b + count
        _, b -> b
      end)

    mx = %Metrics{
      node: length(nodes),
      edge: length(edges),
      head: Map.fetch!(histo, root_ipid),
      final: final,
      branch: branch,
      leaf: 1
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
    {vmol, edges} = dump_recv(1, Mol.new(), [])

    verts =
      Enum.reduce(vmol, [], fn {{id, type}, labels}, verts ->
        label = labels |> Enum.sort() |> Enum.join("\\n")
        [{id, label, type} | verts]
      end)

    {
      Enum.sort_by(verts, &elem(&1, 1)),
      Enum.sort_by(edges, &elem(&1, 1))
    }
  end

  @type vert_mol() :: %{{vert_id(), vert_type()} => [String.t()]}

  # receive dump messages with node and edge data
  # the count of nodes yet to report starts at 1
  # each node report decrements the count by one
  # but each outgoing edge increments the count by 1
  @spec dump_recv(non_neg_integer(), vert_mol(), edges()) :: tree()

  defp dump_recv(0, nodes, edges), do: {nodes, edges}

  defp dump_recv(n, nodes, edges) do
    receive do
      {:node, id, label, final?, out_edges} ->
        type =
          cond do
            final? -> :final
            label == "" -> :initial
            true -> :normal
          end

        # there will be multiple node entries for the sink node
        # so keep a list of all the terminal strings
        new_nodes = Mol.add(nodes, {id, type}, label)

        new_edges =
          Enum.reduce(out_edges, edges, fn {c, pid}, edges ->
            [{id, <<c::utf8>>, Exa.Process.ipid(pid)} | edges]
          end)

        dump_recv(n - 1 + map_size(out_edges), new_nodes, new_edges)
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
        {id, "", :initial}, dot ->
          DOT.node(dot, id, color: ncol, shape: :point)

        {id, name, :normal}, dot ->
          DOT.node(dot, id, label: name, color: ncol, shape: :ellipse)

        {id, name, :final}, dot ->
          DOT.node(dot, id, label: name, color: ncol, shape: :doublecircle)
      end)
      |> DOT.reduce(edges, fn {src, label, dst}, dot ->
        DOT.edge(dot, src, dst, color: ecol, label: label)
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
  # this self process is the executor to receive replies
  @spec dispatch(trie(), any()) :: any()
  defp dispatch({:trie, root, _sink}, msg), do: send(root, {self(), msg})
end
