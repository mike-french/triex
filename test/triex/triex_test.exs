defmodule Triex.TriexTest do
  use ExUnit.Case
  import Triex

  doctest Triex

  # @out_dir Path.join(["test", "output"])

  test "simple" do
    trie = new()

    assert not match(trie, "")
    assert not match(trie, "a")
    assert not match(trie, "x")

    add(trie, ["abc","a","abcdef"])

    assert match(trie, "a")
    assert match(trie, "abc")
    assert match(trie, "abcdef")

    assert not match(trie, "")
    assert not match(trie, "x")
    assert not match(trie, "b")
    assert not match(trie, "ab")
    assert not match(trie, "abxy")
    assert not match(trie, "abcd")
    assert not match(trie, "abcdxyz")
  end
end
