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

    add(trie, ["abc", "a", "xyz", "abcdef", "abcpqr"])

    assert match(trie, "a")
    assert match(trie, "abc")
    assert match(trie, "abcdef")
    assert match(trie, "abcpqr")
    assert match(trie, "xyz")

    assert not match(trie, "")
    assert not match(trie, "x")
    assert not match(trie, "b")
    assert not match(trie, "ab")
    assert not match(trie, "abxy")
    assert not match(trie, "abcd")
    assert not match(trie, "abcdxyz")
    assert not match(trie, "xyzabc")
  end

  test "unicode" do
    trie = new(["好久不见", "龙年"])

    assert match(trie, "好久不见")
    assert match(trie, "龙年")

    assert not match(trie, "")
    assert not match(trie, "好久")
    assert not match(trie, "龙")
    assert not match(trie, "黑龙江")
  end

  test "dump" do
    trie = new(["abc", "a", "xyz", "abcdef", "abcpqr"])
    tree = dump(trie)

    assert {[
              {"", :initial},
              {"a", :final},
              {"ab", :normal},
              {"abc", :final},
              {"abcd", :normal},
              {"abcde", :normal},
              {"abcdef", :final},
              {"abcp", :normal},
              {"abcpq", :normal},
              {"abcpqr", :final},
              {"x", :normal},
              {"xy", :normal},
              {"xyz", :final}
            ],
            [
              {"", "a"},
              {"", "x"},
              {"a", "ab"},
              {"ab", "abc"},
              {"abc", "abcd"},
              {"abc", "abcp"},
              {"abcd", "abcde"},
              {"abcde", "abcdef"},
              {"abcp", "abcpq"},
              {"abcpq", "abcpqr"},
              {"x", "xy"},
              {"xy", "xyz"}
            ]} == tree
  end
end
