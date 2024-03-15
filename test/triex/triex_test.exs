defmodule Triex.TriexTest do
  use ExUnit.Case

  use Exa.Dot.Constants

  alias Exa.CharStream

  import Triex
  alias Triex.Types, as: T

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
    trie = new(["abc", "a", "xyz", "abcdef", "abcpqr"])

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

    teardown(trie)
  end

  test "unicode" do
    trie = new(["好久不见", "龙年"])

    assert match(trie, "好久不见")
    assert match(trie, "龙年")

    assert not match(trie, "")
    assert not match(trie, "好久")
    assert not match(trie, "龙")
    assert not match(trie, "黑龙江")

    teardown(trie)
  end

  test "dump" do
    trie = new(["abc", "a", "xyz", "abcdef", "abcpqr"])
    info = info(trie)

    assert %T.Metrics{
             node: 11,
             edge: 12,
             root: 1,
             head: 2,
             branch: 2,
             final: 3,
             leaf: 1
           } = info

    {verts, edges} = dump(trie)

    assert [
             {_, "", :initial},
             {_, "a", :final},
             {_, "ab", :normal},
             {_, "abc", :final},
             {_, "abcd", :normal},
             {_, "abcde", :normal},
             {_, "abcdef\\nabcpqr\\nxyz", :final},
             {_, "abcp", :normal},
             {_, "abcpq", :normal},
             {_, "x", :normal},
             {_, "xy", :normal}
           ] = verts

    assert [
             {_, "a", _},
             {_, "b", _},
             {_, "c", _},
             {_, "d", _},
             {_, "e", _},
             {_, "f", _},
             {_, "p", _},
             {_, "q", _},
             {_, "r", _},
             {_, "x", _},
             {_, "y", _},
             {_, "z", _}
           ] = edges

    teardown(trie)
  end

  test "dump dot" do
    file = dot_file("abc")
    trie = new(["abc", "a", "xyz", "abcdef", "abcpqr"])
    dump_dot(trie, file)
    teardown(trie)
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

    teardown(trie)
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

    assert hd(result["ipsum"]) == {1, 7, 7}
    assert hd(result["nulla"]) == {1, 251, 251}
    assert hd(result["magna"]) == {3, 282, 1003}

    teardown(trie)
  end

  @words [
    "walk",
    "talk",
    "walking",
    "talking",
    "wall",
    "king",
    "page",
    "pages",
    "paging",
    "wag",
    "wage",
    "wages"
  ]

  test "info" do
    winfo = do_info(@words, "words")

    assert %T.Metrics{
             node: 19,
             edge: 24,
             head: 4,
             final: 6,
             branch: 4,
             leaf: 1,
             root: 1
           } = winfo
  end

  defp do_info(words, name) do
    trie = new(words)
    info = info(trie)
    dump(trie)
    file = dot_file(name)
    dump_dot(trie, file)
    teardown(trie)
    info
  end
end
