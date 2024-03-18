defmodule Triex.Node do
  @moduledoc """
  The processing node of a trie.

  There are two phases: 
  - build construction (bnode)
  - match operation (mnode)
  """

  use Triex.Constants

  alias Exa.Std.Mol

  # -----
  # types
  # -----

  # outgoing edges are indexed by character for transition to child pid
  @typep edgemap() :: %{char() => pid()}

  # incoming edge to a node, character and parent pid
  @typep revedge() :: {char(), pid()}

  # incoming edges are one-many character to pid list (MoL)
  @typep revedges() :: %{char() => [pid(), ...]}

  defguardp is_sink(final?, edges, _) when final? and edges == %{}

  # ----------------
  # public functions
  # ----------------

  @doc """
  Start the process with a terminal flag, 
  but without any parent reverse edge.
  Only used for root and sink.
  """
  @spec start(bool()) :: pid()
  def start(final?) do
    spawn_link(__MODULE__, :init, [final?, %{}])
  end

  @doc """
  Start an internal process with a terminal flag 
  and a parent reference.
  """
  @spec start(bool(), revedge()) :: pid()
  def start(final?, {c, pid}) do
    spawn_link(__MODULE__, :init, [final?, Mol.new() |> Mol.add(c, pid)])
  end

  @spec init(bool(), revedges()) :: no_return()
  def init(final?, revedges), do: b_node(final?, %{}, revedges)

  # ----------
  # build node
  # ----------

  @spec b_node(bool(), forward :: edgemap(), reverse :: revedges()) :: no_return()
  defp b_node(final?, edges, revedges) do
    receive do
      # add ----------
      # mostly tree-based constructor with a single final node (sink)

      {exec, {:add_word, <<c::utf8, rest::binary>>, sink}} when is_map_key(edges, c) ->
        # existing path, just propagate the add request
        send(Map.fetch!(edges, c), {exec, {:add_word, rest, sink}})

      {exec, {:add_word, <<c::utf8>>, sink}} ->
        # last link goes to the sink, so end traversal
        send(sink, {:add_rev, c, self()})
        send(exec, {:add_word, :ok})
        b_node(final?, Map.put(edges, c, sink), revedges)

      {exec, {:add_word, <<c::utf8, rest::binary>>, sink}} ->
        # no existing path, spawn a new child node
        pid = start(false, {c, self()})
        # continue traversal to the new node
        send(pid, {exec, {:add_word, rest, sink}})
        b_node(final?, Map.put(edges, c, pid), revedges)

      {exec, {:add_word, <<>>, _sink}} ->
        # new final node within existing structure
        send(exec, {:add_word, :ok})
        b_node(true, edges, revedges)

      # suffixes ----------
      # reverse traversals from sink:
      # - build suffix map
      # - merge suffixes: find copies, redirect and kill duplicates

      # build suffix 

      {exec, :suffix_build} when is_sink(final?, edges, revedges) ->
        # start reverse traversal in the sink
        sufmap =
          Enum.reduce(revedges, %{}, fn {c, pids}, sufmap ->
            Enum.reduce(pids, sufmap, fn pid, sufmap ->
              send(pid, {self(), {:suffix_build, [c], sufmap}})

              receive do
                {:suffix_build, new_sufmap} -> new_sufmap
              after
                @timeout -> raise RuntimeError, message: "Timeout"
              end
            end)
          end)

        send(exec, {:suffix_build, sufmap})

      {sink, {:suffix_build, tail, sufmap}}
      when final? or map_size(edges) > 1 or map_size(revedges) == 0 ->
        # hit a final node or branching node, so cancel all suffixes
        # remove the tail and all longer suffixes with the same tail
        liat = Enum.reverse(tail)

        new_sufmap =
          Enum.reduce(Map.keys(sufmap), sufmap, fn key, sufmap ->
            if length(key) >= length(tail) and
                 List.starts_with?(Enum.reverse(key), liat) do
              Map.delete(sufmap, key)
            else
              sufmap
            end
          end)

        # terminate reverse traversal
        send(sink, {:suffix_build, new_sufmap})

      {sink, {:suffix_build, tail, sufmap}} ->
        # propagate non-final linear chain
        [{r, [next_pid]}] = Map.to_list(revedges)
        new_tail = [r | tail]
        new_sufmap = Map.put(sufmap, new_tail, self())
        send(next_pid, {sink, {:suffix_build, new_tail, new_sufmap}})

      # merge suffix 

      {exec, {:suffix_merge, sufmap}} when is_sink(final?, edges, revedges) ->
        # start reverse traversal in the sink
        Enum.reduce(revedges, 1, fn {c, pids}, n ->
          Enum.reduce(pids, n, fn pid, n ->
            send(pid, {self(), {:suffix_merge, [c], sufmap}})

            receive do
              {:suffix_merge, :ok} -> n + 1
            after
              @timeout -> raise RuntimeError, message: "Timeout"
            end
          end)
        end)

        send(exec, {:suffix_merge, :ok})

      {sink, {:suffix_merge, [c | _] = tail, sufmap}} ->
        # match tail and test for reuse of the same suffix 
        new_edges =
          cond do
            is_map_key(sufmap, tail) and
                Map.fetch!(sufmap, tail) != Map.fetch!(edges, c) ->
              # replace the old forward path with the shared suffix
              # kill the old forward node
              oldpid = Map.fetch!(edges, c)
              send(oldpid, {:EXIT, :suffix})
              # reference the shared suffix
              sufpid = Map.fetch!(sufmap, tail)
              # add the new parent to the head of the suffix
              send(sufpid, {:add_rev, c, self()})
              Map.replace!(edges, c, sufpid)

            length(tail) == 1 and not final? ->
              # initial step up from sink is never in the suffix map
              # continue traversal
              edges

            true ->
              # no suffix match, or final node, terminate traversal
              send(sink, {:suffix_merge, :ok})
              b_node(final?, edges, revedges)
          end

        # continue traversal up to original parent
        # first parent is the hd because extra refs are appended
        [{r, [parent | _]}] = Map.to_list(revedges)
        send(parent, {sink, {:suffix_merge, [r | tail], sufmap}})
        b_node(final?, new_edges, revedges)

      {:EXIT, :suffix} ->
        # stop a duplicate suffix process
        # remove reverse edges from children
        # (in practice, only ever a single child edge)
        Enum.each(edges, fn {c, pid} -> send(pid, {:del_rev, c, self()}) end)
        exit(:normal)

      {:add_rev, c, pid} ->
        # add a reverse parent link to sink node
        # and the heads of shared suffixes during merge
        # appending keeps the original parent at the head
        b_node(final?, edges, Mol.append(revedges, c, pid))

      {:del_rev, c, pid} ->
        # delete a reverse parent link when nodes are killed
        b_node(final?, edges, Mol.remove(revedges, c, pid))

      # freeze ----------
      # convert to match runtime mode

      {exec, :freeze} = msg ->
        send(exec, {:freeze, map_size(edges)})
        Enum.each(edges, fn {_, pid} -> send(pid, msg) end)
        m_node(final?, edges)

      any ->
        throw({:unhandled_message, [__MODULE__, any]})
    end

    b_node(final?, edges, revedges)
  end

  # ----------
  # match node
  # ----------

  @spec m_node(bool(), forward :: edgemap()) :: no_return()
  defp m_node(final?, edges) do
    receive do
      # match ----------

      {exec, {:match, <<>>}} ->
        # empty string at terminal node is success
        # empty string at non-terminal node is failure
        send(exec, {:matched, final?})

      {exec, {:match, <<c::utf8, rest::binary>>}} when is_map_key(edges, c) ->
        # next character already has a valid transition
        send(Map.fetch!(edges, c), {exec, {:match, rest}})

      {exec, {:match, _str}} ->
        # still some unmatched input
        # we are not the final answer
        # there are no more matched transitions, so failure
        send(exec, {:matched, false})

      # dump ----------

      {exec, {:dump, str}} ->
        send(exec, {:node, Exa.Process.ipid(), str, final?, edges})

        Enum.each(edges, fn {c, pid} ->
          send(pid, {exec, {:dump, <<str::binary, c::utf8>>}})
        end)

      # freeze ----------

      {exec, :freeze} ->
        send(exec, {:freeze, 0})

      # teardown ----------

      {exec, {:EXIT, :teardown}} = msg ->
        send(exec, {:teardown, :ok})
        Enum.each(edges, fn {_, pid} -> send(pid, msg) end)
        exit(:normal)

      any ->
        throw({:unhandled_message, [__MODULE__, any]})
    end

    m_node(final?, edges)
  end
end
