## Triex

String trie lookup using tree of processes (Elixir).

## Design

The trie is built as a tree of independent processes.

The implementation is based on the idea of _Process Oriented Programming:_ 
* Algorithms are implemented using a fine-grain directed graph of 
  independent share-nothing processes.
* Processes communicate asynchronously by passing messages. 
* Process networks naturally run in parallel.

Each process (node) has:
- Flag to indicate if it is a matching terminal state.
- Map of matching characters to the next (child) process 
  in the tree (outgoing edges).
  
Note that partial/final strings are not stored in the nodes:
nodes do not know the string or prefix that they match.

Traversals of the tree are implemented as a sequence of messages
propagating down one path within the tree.

There are two main kinds of traversals: _add_ and _match._

The traversal messages contain a source/target string.
At each step of the traversal, 
one character is consumed from the head of the string.

Each addition or match is a single traversal, 
so it cannot be parallelized.
Additions are blocking synchronous traversals.
However, multiple match traversals can propagate concurrently,
because all state is in the traversal messages, not in the nodes.

### Optimization Note

All leaf nodes are matching terminal nodes with no onward edges.
So they are all equivalent, and could be implemented by a single process,
with convergence of the tree (DAG).
But that would make it difficult to extend the tree
by adding new strings to the trie.
One solution would be to order additions from longest to shortest,
so there is never extension beyond an existing termination
(assuming all accepted strings are known in advance).

In fact, all common suffices without intermediate termination, 
could be factored out and reused.
This would reduce the process count for common parts of speech
(e.g. in English "-ed", "-ing", "-ly").
However there is no obvious and efficient bidirectional
incremental way to build the trie, so it would have to be implemented 
as a compilation post-process after all accepted strings have been added.

## API

There are 4 public functions:
- `new`: build a new empty trie
- `add`: add one or more strings to the trie
- `match`: test if a complete string is in the trie
- `dump`: returns the tree structure 
  
`new` creates a new trie containing a root node (process).
There is a convenience version that accepts 
a list of strings to add to the new trie.

`add` adds one or more new strings to the trie. 
The api function initiates an _add_ traversal of the tree for each new string. 
The traversal passes through existing nodes that match a prefix of the new string.
If there is no onward path, new child nodes are spawned,
and the traversal continues (like laying the track in front of the train).
When the new string is consumed,
the last node is marked as a terminal _success_ node.

`match` tests if a complete string is included in the trie.
The api function initiates a _match_ traversal of the tree. 
The traversal passes through nodes that match a prefix of the new string.
If the string is all consumed, and the last visited node is a terminal node,
then the result is success (true).
The result is failure (false) if either:
- the string is not consumed, and there is no onward path
- the string is consumed, but the last visited node is not a terminal node.

`dump` returns structure informtion for the node processes
and edge transitions in the trie. 
The nodes and edges can be reconstructed into the tree state machine.
(TODO - GraphViz DOT conversion and rendering).
The dump traversal starts from the root.
Each node returns its info, then propagates the `dump` message
to _all_ its child processes along outgoing edges (fan-out).
The traversal manages the current prefix match to label nodes.
The spawning api function collates all the returned info
and keeps a count of how many nodes have yet to report.

## Install

The package can be installed
by adding `triex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:triex, git: "https://github.com/mike-french/triex.git", tag: "1.0.0"}
  ]
end
```

## Project 

Compile the project:

`mix deps.get`

`mix compile`

Run dialyzer for type analysis:

`mix dialyzer`

Run the tests (excluding benchmarks):

`mix test`

Run benchmarks:

`mix test --only: benchmark:true`

Generate the documentation:

`mix docs`

## License

Triex source code is released under the MIT license.

The code and the documentation are:
Copyright (C) 2024 Mike French
