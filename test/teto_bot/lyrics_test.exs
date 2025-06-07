defmodule TetoBot.LyricsTest do
  use ExUnit.Case, async: false
  alias TetoBot.Lyrics

  setup do
    # Clear Redis before each test
    {:ok, _} = Redix.command(:redix, ["FLUSHALL"])
    :ok
  end

  describe "store_lyrics/3" do
    test "stores lyrics in Redis" do
      assert :ok = Lyrics.store_lyrics("Test Song", "Test Artist", "Test lyrics")
      assert {:ok, "Test lyrics"} = Lyrics.get_lyrics("Test Song", "Test Artist")
    end
  end

  describe "get_lyrics/2" do
    test "returns {:error, :not_found} when lyrics don't exist" do
      assert {:error, :not_found} = Lyrics.get_lyrics("Nonexistent", "Artist")
    end
  end

  describe "list_lyrics/0" do
    test "returns list of stored lyrics" do
      assert :ok = Lyrics.store_lyrics("Song 1", "Artist 1", "Lyrics 1")
      assert :ok = Lyrics.store_lyrics("Song 2", "Artist 2", "Lyrics 2")

      assert {:ok, songs} = Lyrics.list_lyrics()
      assert length(songs) == 2
      assert %{artist: "Artist 1", song: "Song 1"} in songs
      assert %{artist: "Artist 2", song: "Song 2"} in songs
    end

    test "returns empty list when no lyrics are stored" do
      assert {:ok, []} = Lyrics.list_lyrics()
    end
  end
end
