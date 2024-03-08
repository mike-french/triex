defmodule Triex.TriexTest do
  use ExUnit.Case

  use Exa.Dot.Constants

  alias Exa.CharStream

  import Triex

  doctest Triex

  @lorem ~S"""
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. 
    Mauris egestas nisi eget sapien commodo semper. 
    Nunc volutpat velit eu erat euismod, quis pharetra eros pharetra. 
    Proin scelerisque metus viverra nibh volutpat, 
    posuere consequat quam laoreet. 
    Nulla elementum sollicitudin tortor et scelerisque. 
    Quisque dignissim tempus dui, nec auctor tellus elementum eget. 
    Quisque auctor ex eros, sit amet fermentum neque porta eu. 
    Pellentesque at molestie ligula, sed accumsan odio. 
    Vestibulum iaculis mollis risus, sed tincidunt sem sollicitudin ac. 
    Aliquam ac turpis in risus varius congue non sit amet mi. 
    Phasellus vitae sodales lacus, non condimentum lectus. 
    Interdum et malesuada fames ac ante ipsum primis in faucibus.
  """

  @filetype_txt "txt"
  @in_dir Path.join(["test", "input"])
  defp in_file(name), do: Exa.File.join(@in_dir, name, @filetype_txt)

  @dot_dir Path.join(["test", "output", "dot"])
  defp dot_file(name), do: Exa.File.join(@dot_dir, name, @filetype_dot)

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
              {"a", "b"},
              {"ab", "c"},
              {"abc", "d"},
              {"abc", "p"},
              {"abcd", "e"},
              {"abcde", "f"},
              {"abcp", "q"},
              {"abcpq", "r"},
              {"x", "y"},
              {"xy", "z"}
            ]} == tree
  end

  test "dump dot" do
    file = dot_file("abc")
    trie = new(["abc", "a", "xyz", "abcdef", "abcpqr"])
    dump_dot(trie, file)
  end

  test "matches" do
    trie =
      new([
        "nunc",
        "nulla",
        "magna",
        "ipsum"
      ])

    toks = CharStream.tokenize(@lorem)
    result = matches(trie, toks)

    assert %{
             "ipsum" => [{1, 9, 9}, {13, 39, 733}],
             "nulla" => [{6, 3, 268}],
             "nunc" => [{3, 3, 114}]
           } == result
  end

  test "file" do
    trie =
      new([
        "nunc",
        "nulla",
        "magna",
        "ipsum"
      ])

    file = in_file("lorem_ipsum")
    result = match_file(trie, file)

    assert %{
             "ipsum" => [{1, 9, 9}, {13, 39, 733}],
             "nulla" => [{6, 3, 268}],
             "nunc" => [{3, 3, 114}]
           } == result
  end
end
