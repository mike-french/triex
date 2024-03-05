## Triex

String trie lookup using tree of processes (Elixir).

## Design

The trie is built as a tree of independent processes.
Each process has:
- flag to indicate if it is a matching terminal node
- map of characters to the next (child) process in the tree

Traversals of the tree are implemented as a sequence of messages
propagating down one path within the tree.
There are two kinds of traversals: _add_ and _match._
The traversal messages contain a string.
At each step of the traversal, 
one character is consumed from the head of the string.
Each match is a single traversal, so it cannot be parallelized.

TODO - spawn executor processes so each match is executed in parallel.

## API

There are 3 public functions:
- new: build a new empty trie
- add: add a string to the trie
- match: test if a string is in the trie

`new` creates a new trie tuple containing a root node (process).

`add` adds one or more new strings to the trie. 
The api function initiates an _add_ traversal of the tree for each new string. 
The traversal passes through existing nodes that match a prefix of the new string.
If there is no onward path, new child nodes are spawned,
and the traversal continues. 
When the new string is consumed,
the last node is marked as a terminal _success_ node.

`match` tests if a string is included in the trie.
The api function initiates a _match_ traversal of the tree. 
The traversal passes through nodes that match a prefix of the new string.
If the string is all consumed, and the last visited node is a terminal node,
then the result is success (true).
The result is failure (false) if either:
- the string is not consumed, and there is no onward path
- the string is consumed, but the last visited node is not a terminal node

## Install

The package can be installed
by adding `triex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:triex, "~> 0.1.0"}
  ]
end
```

## Test

Run all Triex tests, excluding benchmarks:

`$ mix test`

## License

Triex source code is released under the MIT license.

The code and the documentation are:
Copyright (C) 2024 Mike French
