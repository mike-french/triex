defmodule Triex do
  @moduledoc "The Triex trie interface."

  use Triex.Constants

  import Exa.Types
  alias Exa.Types, as: E

  alias Exa.Std.Mol
  alias Exa.Std.Mol, as: M

  alias Exa.CharStream

  alias Exa.Gfx.Color.Col3f

  alias Exa.Dot.DotWriter, as: DOT
  alias Exa.Dot.Render

  import Triex.Types
  alias Triex.Types, as: T

  alias Triex.Node

  # -----------
  # local types 
  # -----------

  # trie structure used during construction
  @typep btrie() :: {:triex, root :: pid(), sink :: pid()}

  # suffix map used during construction
  @typep sufmap() :: %{charlist() => pid()}

  # -----------
  # constructor 
  # -----------

  @doc "Create a new trie with a set of target strings."
  @spec start([String.t(), ...]) :: T.trie()
  def start(strs) when is_nonempty_list(strs) do
    # root is never final, and never has parent reverse links
    # sink is always final, has no initial parents, but will have some added
    root = Node.start(false)
    btrie = {:triex, root, Node.start(true)}
    # sorting words by length ensures long paths to the sink are built first
    # later prefix words add intermediate final status
    strs |> Enum.sort_by(&String.length/1, :desc) |> Enum.each(&add_word(btrie, &1))
    # find the common suffixes and share them in the DAG
    btrie |> suffix_build() |> suffix_merge(btrie) |> freeze()
  end

  @spec add_word(btrie(), String.t()) :: :ok
  defp add_word({:triex, _, sink} = trie, str) when is_binary(str) do
    dispatch_root(trie, {:add_word, str, sink})

    receive do
      {:add_word, :ok} -> :ok
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @spec suffix_build(btrie()) :: sufmap()
  defp suffix_build(trie) do
    dispatch_sink(trie, :suffix_build)

    receive do
      {:suffix_build, sufmap} -> sufmap
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @spec suffix_merge(sufmap(), btrie()) :: btrie()
  defp suffix_merge(sufmap, trie) do
    dispatch_sink(trie, {:suffix_merge, sufmap})

    receive do
      {:suffix_merge, :ok} -> trie
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # convert add build mode into runtime match mode
  @spec freeze(trie :: btrie()) :: T.trie()
  defp freeze({:triex, root, _} = trie) do
    dispatch_root(trie, :freeze)
    freeze_recv(1)
    {:triex, root}
  end

  defp freeze_recv(0), do: :ok

  defp freeze_recv(n) do
    receive do
      {:freeze, nedge} -> freeze_recv(n - 1 + nedge)
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # ----------
  # destructor 
  # ----------

  @doc "Stop and delete the triex process network."
  @spec stop(trie :: T.trie()) :: :ok
  def stop(trie) when is_trie(trie) do
    nnodes = nnodes(trie)
    dispatch_root(trie, {:EXIT, :teardown})
    teardown_recv(nnodes)
  end

  defp teardown_recv(0), do: :ok

  defp teardown_recv(n) do
    receive do
      {:teardown, :ok} -> teardown_recv(n - 1)
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # -----
  # match
  # -----

  @doc "Test a complete match of a single string in the triex (blocking)."
  @spec match(T.trie(), String.t()) :: bool()
  def match(trie, str) when is_trie(trie) do
    dispatch_root(trie, {:match, str})

    receive do
      {:matched, result} -> result
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @doc """
  Test multiple words for a complete match in the triex (parallel).

  The input strings are paired with an opaque application reference,
  which will be returned with the string in the result.
  The reference is typically a location in the text source, 
  such as:
  - character number `nchar`
  - `{line, column}`
  - `{filename, line, column}`

  The return value is a Map of Lists,
  with matched strings as the keys,
  and a list of references for the matches.
  """
  @spec matches(T.trie(), [{String.t(), any()}]) :: M.mol()
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

  @doc """
  Match all tokens in a file against the triex.

  The return value is a Map of Lists,
  with matched strings as the keys,
  and a list of references for the matches.

  The references are in the form of 
  See Exa.CharStream for the tokenization 
  and format of the file address references.

  """
  @spec match_file(T.trie(), E.filename()) :: M.mol()
  def match_file(trie, filename) when is_filename(filename) do
    toks = filename |> Exa.File.from_file_text() |> CharStream.tokenize()
    matches(trie, toks)
  end

  # ----
  # dump
  # ----

  @doc """
  Get structural metrics from the triex (blocking, parallelized).
  Optionally print the result.

  Returns the Metrics (see type definition).
  """
  @spec info(T.trie(), bool()) :: %T.Metrics{}
  def info({:triex, root} = trie, print? \\ true) when is_pid(root) do
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

    mx = %T.Metrics{
      node: length(nodes),
      edge: length(edges),
      head: Map.fetch!(histo, root_ipid),
      final: final,
      branch: branch
    }

    if print? do
      IO.puts("Trie info:")
      IO.puts("  node:   #{mx.node}")
      IO.puts("  edge:   #{mx.edge}")
      IO.puts("  root:   #{mx.root}")
      IO.puts("  head:   #{mx.head}")
      IO.puts("  branch: #{mx.branch}")
      IO.puts("  final:  #{mx.final}")
      IO.puts("  leaf:   #{mx.leaf}")
    end

    mx
  end

  @doc """
  Gather structural information about the triex process network
  (blocking, parallelized).
  """
  @spec dump(T.trie()) :: T.graph_info()
  def dump(trie) when is_trie(trie) do
    dispatch_root(trie, {:dump, ""})
    dump_recv(1, Mol.new(), MapSet.new())
  end

  @typep vert_mol() :: %{{T.vert_id(), T.vert_type()} => [String.t()]}

  # receive dump messages with node and edge data
  # the count of nodes yet to report starts at 1
  # each node report decrements the count by one
  # but each outgoing edge increments the count by 1
  @spec dump_recv(E.count(), vert_mol(), MapSet.t()) :: T.graph_info()

  defp dump_recv(0, nodemap, edgeset) do
    # build multi-line label where paths merge
    # used for merged suffixes and the sink node
    verts =
      Enum.reduce(nodemap, [], fn {{id, type}, labels}, verts ->
        label = labels |> Enum.sort() |> Enum.join("\\n") |> Exa.String.summary(30)
        [{id, label, type} | verts]
      end)

    {
      verts |> Enum.sort_by(&elem(&1, 1)),
      edgeset |> MapSet.to_list() |> Enum.sort_by(&elem(&1, 1))
    }
  end

  defp dump_recv(n, nodes, edgeset) do
    receive do
      {:node, id, label, final?, out_edges} ->
        type =
          cond do
            final? -> :final
            label == "" -> :initial
            true -> :normal
          end

        # there will be multiple node entries for 
        # merged suffixes and the sink node
        # so keep a list of all the strings
        new_nodes = Mol.add(nodes, {id, type}, label)

        new_edgeset =
          Enum.reduce(out_edges, edgeset, fn {c, pid}, edgeset ->
            MapSet.put(edgeset, {id, <<c::utf8>>, Exa.Process.ipid(pid)})
          end)

        dump_recv(n - 1 + map_size(out_edges), new_nodes, new_edgeset)
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  # special dump traversal to just count the number of nodes
  @spec nnodes(T.trie()) :: E.count1()
  defp nnodes(trie) when is_trie(trie) do
    dispatch_root(trie, {:dump, ""})
    nnode_recv(1, MapSet.new())
  end

  @spec nnode_recv(E.count(), MapSet.t()) :: E.count1()

  defp nnode_recv(0, nodeset), do: MapSet.size(nodeset)

  defp nnode_recv(n, nodeset) do
    receive do
      {:node, id, _, _, _} -> nnode_recv(n - 1, MapSet.put(nodeset, id))
    after
      @timeout -> raise RuntimeError, message: "Timeout"
    end
  end

  @doc """
  Gather structural info from the triex,
  convert to GraphViz DOT format and 
  optionally render as PNG 
  (if GraphViz is installed).
  """
  @spec dump_dot(T.trie(), E.filename(), bool()) :: String.t()
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

  # send a message to the root node for forward traversal
  # this self process is the executor to receive replies
  @spec dispatch_root(T.trie() | btrie(), any()) :: any()
  defp dispatch_root({:triex, root}, msg), do: send(root, {self(), msg})
  defp dispatch_root({:triex, root, _}, msg), do: send(root, {self(), msg})

  # send a message to the sink node for reverse traversal
  # this self process is the executor to receive replies
  @spec dispatch_sink(btrie(), any()) :: any()
  defp dispatch_sink({:triex, _, sink}, msg), do: send(sink, {self(), msg})
end
