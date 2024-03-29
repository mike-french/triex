defmodule Triex.Types do
  @moduledoc "Types for Triex."

  alias Exa.Types, as: E

  # -----
  # types 
  # -----

  @typedoc "A Triex structure."
  @type trie() :: {:triex, root :: pid()}
  defguard is_trie(t)
           when is_tuple(t) and tuple_size(t) == 2 and
                  elem(t, 0) == :triex and is_pid(elem(t, 1))

  # types for tree info returned by 'dump'
  # 'node' is a reserved type, so use vert instead

  @typedoc """
  Node type for DOT graph output.
  The type determines the node representation in diagrams.

  There are three types:
  - `:initial` means the virtual root, there is only 1 root
  - `:normal` means any internal (non-leaf) node 
    that is not a member of the trie
    so traversals always continue
  - `:final` means a node that is a member of the trie
    where traversals may terminate,
    it includes some zero or more internal nodes 
    and one final sink (leaf) node
  """
  @type vert_type() :: :initial | :normal | :final
  @type vert_id() :: pos_integer()
  @type vert() :: {vert_id(), vert_label :: String.t(), vert_type()}
  @type verts() :: [vert()]

  @type edge() :: {src :: vert_id(), edge_label :: String.t(), dst :: vert_id()}
  @type edges() :: [edge()]

  @type graph_info() :: {verts(), edges()}

  defmodule Metrics do
    @moduledoc "Metrics for counts of trie structure nodes and edges:"
    defstruct [:node, :edge, :head, :final, :branch, leaf: 1, root: 1]
  end

  @typedoc """
  Metrics for counts of trie structure:
  - _node:_ total number of nodes, including the root 
  - _edge:_ total number of edges
  - _root:_ the number of root nodes (1)
  - _head:_ number of edges leaving the root
  - _final:_ number of nodes that can return a successful result
  - _branch:_ number of nodes that have more than one outgoing edge
  - _leaf:_ number of nodes that do not have any outgoing edges (1)
            
  The number of heads is equal to the number of 
  distinct starting letters of words in the trie.
  It is the number of edges from the root node.

  Branches occur at the root 
  (empty string is a common prefix for all words)
  and when there are common prefixes within the trie.

  Final nodes always include the sink node,
  plus any internal nodes that match a word 
  which is a prefix of another valid word.

  There is only one root.

  There is only one sink (leaf).
  """
  @type metrics() :: %Metrics{
          node: E.count1(),
          edge: E.count(),
          head: E.count(),
          final: E.count(),
          branch: E.count(),
          leaf: 1,
          root: 1
        }
end
