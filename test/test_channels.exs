defmodule TetoBot.ChannelsTest do
  use TetoBot.DataCase, async: true

  import TetoBot.Factory
  import Mox

  setup do
    :verify_on_exit!
    :ok
  end

  describe "whitelist_channel/1" do
    test "successfully whitelists a valid channel ID and adds to cache" do
      channel_id = 123_456_789
      expect(TetoBot.Channels.CacheMock, :add, fn ^channel_id -> :ok end)

      channel = build(:channel, channel_id: channel_id)

      expect(TetoBot.RepoMock, :insert, fn changeset, _opts ->
        assert %Ecto.Changeset{
                 data: %TetoBot.Channels.Channel{},
                 changes: %{channel_id: ^channel_id}
               } = changeset

        {:ok, channel}
      end)

      assert {:ok, %TetoBot.Channels.Channel{channel_id: ^channel_id}} =
               TetoBot.Channels.whitelist_channel(channel_id)
    end

    test "returns error when database insert fails" do
      channel_id = 123_456_789

      # Create a more realistic invalid changeset
      invalid_changeset =
        %TetoBot.Channels.Channel{}
        # or whatever makes it invalid
        |> TetoBot.Channels.Channel.changeset(%{channel_id: "invalid_id"})

      # Expect insert to be called and return the error
      expect(TetoBot.RepoMock, :insert, fn _changeset, _opts ->
        {:error, invalid_changeset}
      end)

      # Verify cache is not called when insert fails
      deny(TetoBot.Channels.CacheMock, :add, 1)

      # Test the actual function
      assert {:error, changeset} = TetoBot.Channels.whitelist_channel(channel_id)
      assert changeset == invalid_changeset
      refute changeset.valid?
    end
  end

  describe "blacklist_channel/1" do
    test "successfully removes a whitelisted channel and updates cache" do
      channel_id = 123_456_789
      channel = build(:channel, channel_id: channel_id)

      expect(TetoBot.RepoMock, :get_by, fn TetoBot.Channels.Channel,
                                           [channel_id: ^channel_id],
                                           _ ->
        channel
      end)

      expect(TetoBot.RepoMock, :delete, fn ^channel, _opts ->
        {:ok, channel}
      end)

      expect(TetoBot.Channels.CacheMock, :remove, fn ^channel_id -> :ok end)

      assert {:ok, %TetoBot.Channels.Channel{channel_id: ^channel_id}} =
               TetoBot.Channels.blacklist_channel(channel_id)
    end

    test "returns error when channel is not found" do
      channel_id = 123_456_789

      expect(TetoBot.RepoMock, :get_by, fn TetoBot.Channels.Channel,
                                           [channel_id: ^channel_id],
                                           _ ->
        nil
      end)

      deny(TetoBot.RepoMock, :delete, 2)
      deny(TetoBot.Channels.CacheMock, :remove, 1)

      assert {:error, :not_found} = TetoBot.Channels.blacklist_channel(channel_id)
    end

    test "returns error when database delete fails" do
      channel_id = 123_456_789
      channel = build(:channel, channel_id: channel_id)
      changeset = %Ecto.Changeset{valid?: false, errors: [channel_id: {"invalid", []}]}

      expect(TetoBot.RepoMock, :get_by, fn TetoBot.Channels.Channel,
                                           [channel_id: ^channel_id],
                                           _ ->
        channel
      end)

      expect(TetoBot.RepoMock, :delete, fn ^channel, _opts ->
        {:error, changeset}
      end)

      deny(TetoBot.Channels.CacheMock, :remove, 1)

      assert {:error, ^changeset} = TetoBot.Channels.blacklist_channel(channel_id)
    end
  end

  describe "whitelisted?/1" do
    test "returns true if channel is in cache" do
      channel_id = 123_456_789
      expect(TetoBot.Channels.CacheMock, :exists?, fn ^channel_id -> true end)
      deny(TetoBot.RepoMock, :get_by, 3)
      deny(TetoBot.Channels.CacheMock, :add, 1)

      assert TetoBot.Channels.whitelisted?(channel_id) == true
    end

    test "returns false and does not add to cache if channel is not in database" do
      channel_id = 123_456_789

      expect(TetoBot.Channels.CacheMock, :exists?, fn ^channel_id -> false end)

      expect(TetoBot.RepoMock, :get_by, fn TetoBot.Channels.Channel,
                                           [channel_id: ^channel_id],
                                           _ ->
        nil
      end)

      deny(TetoBot.Channels.CacheMock, :add, 1)

      assert TetoBot.Channels.whitelisted?(channel_id) == false
    end

    test "returns false for non-snowflake input" do
      deny(TetoBot.Channels.CacheMock, :exists?, 1)
      deny(TetoBot.RepoMock, :get_by, 3)
      deny(TetoBot.Channels.CacheMock, :add, 1)

      assert TetoBot.Channels.whitelisted?("invalid") == false
    end

    test "whitelisted? does not cache blacklisted channels" do
      channel_id = 123_456_789

      expect(TetoBot.RepoMock, :get_by, fn Channel, [channel_id: ^channel_id], [] ->
        nil
      end)

      # Cache should not be called since channel is not whitelisted
      deny(TetoBot.Channels.CacheMock, :add, 1)

      # Should return false and not add to cache
      assert TetoBot.Channels.whitelisted?(channel_id) == false
    end

    test "whitelisted? caches whitelisted channels found in database" do
      channel_id = 123_456_789
      channel = %TetoBot.Channels.Channel{channel_id: channel_id}

      # Mock repo to return the channel
      expect(TetoBot.RepoMock, :get_by, fn Channel, [channel_id: ^channel_id], [] ->
        channel
      end)

      # Cache should be called since channel is whitelisted
      expect(TetoBot.Channels.CacheMock, :add, fn ^channel_id -> :ok end)

      assert TetoBot.Channels.whitelisted?(channel_id) == true
    end
  end
end
