defmodule Jido.Campfire.Pages.CampfireTest do
  use Jido.Campfire.HologramPageCase, async: false

  alias Hologram.Component.{Action, Command}
  alias Hologram.Server.Broadcast
  alias Jido.Campfire.Components.Campfire.ThreadPanel
  alias Jido.Campfire.{Chat, Presence}
  alias Jido.Campfire.Pages.Campfire

  setup do
    Presence.reset()

    on_exit(fn ->
      Presence.reset()
    end)

    :ok
  end

  test "init loads the workspace and subscribes the page to workspace broadcasts" do
    {component, server} = init_page(Campfire)

    assert component.state.workspace == %{id: "jido", name: "Jido Campfire"}
    assert component.state.active_room_id == "room:general"
    assert component.state.rail_target == "channels"
    assert Enum.any?(component.state.developer_stack, &(&1.name == "Jido Chat"))
    assert Enum.any?(component.state.developer_contract, &(&1.detail == "Jido.Chat.PostPayload"))
    assert component.state.last_event.title == "Workspace loaded"
    assert Enum.any?(component.state.channels, &(&1.id == "room:general"))
    assert Enum.any?(component.state.channels, &(&1.id == "room:agent-lab"))
    assert Enum.any?(component.state.direct_messages, &(&1.id == "dm:maggie"))
    assert Enum.any?(component.state.direct_messages, &(&1.id == "dm:alice"))
    assert Enum.map(component.state.agent_demo.agents, & &1.name) == ["Alice", "Bob", "Charlie"]
    assert component.state.agent_prompt_draft == ""
    assert component.next_action == %Action{name: :presence_heartbeat, delay: 250}
    assert {{:workspace, Chat.workspace_id()}, "page"} in server.subscriptions
  end

  test "presence heartbeat queues a touch command and reschedules itself" do
    {component, _server} = init_page(Campfire)

    component = Campfire.action(:presence_heartbeat, %{}, component)

    assert %Command{
             name: :touch_presence,
             params: %{user_id: "user:you", room_id: "room:general"}
           } = component.next_command

    assert %Action{name: :presence_heartbeat, delay: delay} = component.next_action
    assert delay == Presence.heartbeat_interval_ms()
  end

  test "touch_presence command broadcasts the live presence projection" do
    server = %Server{cid: "page", instance_id: "presence-test", session_id: "session-test"}

    server =
      Campfire.command(
        :touch_presence,
        %{user_id: "user:maggie", room_id: "room:general"},
        server
      )

    assert [
             %Broadcast{
               channel: {:workspace, "jido"},
               action_name: :presence_changed,
               params: %{
                 presence: %{online_user_ids: online_user_ids},
                 signal: %{type: "jido.messaging.participant.presence_changed"}
               }
             }
           ] = server.broadcasts

    assert "user:maggie" in online_user_ids
  end

  test "presence_changed action queues a fresh read-model snapshot" do
    {component, _server} = init_page(Campfire)

    component =
      Campfire.action(
        :presence_changed,
        %{
          presence: %{online_user_ids: ["user:maggie"]},
          signal: %{type: "jido.messaging.participant.presence_changed"}
        },
        component
      )

    assert %Command{
             name: :load_snapshot,
             params: %{user_id: "user:you", active_room_id: "room:general"}
           } = component.next_command

    assert component.state.last_event.title == "Presence synced"
  end

  test "snapshot_loaded reflects presence from the server read model" do
    {component, _server} = init_page(Campfire)

    refute Enum.find(component.state.direct_messages, &(&1.id == "dm:maggie")).online

    assert {:ok, _presence, _signals} =
             Chat.touch_presence("user:maggie", "room:general", session_id: "snapshot-presence")

    component = Campfire.action(:snapshot_loaded, %{snapshot: Chat.snapshot()}, component)

    maggie = Enum.find(component.state.direct_messages, &(&1.id == "dm:maggie"))
    assert maggie.online
    assert maggie.member_count_label == "online"
  end

  test "template evaluates against initialized page state" do
    {component, _server} = init_page(Campfire)

    assert [{:element, "main", _attrs, _children}] = Campfire.template().(component.state)
  end

  test "send_message action validates blank drafts before queueing a server command" do
    {component, _server} = init_page(Campfire)
    component = put_page_state(component, :draft, "   ")

    component = Campfire.action(:send_message, %{}, component)

    assert component.state.error == "Type a message first."
    refute component.next_command
  end

  test "send_message action clears the composer and queues a persistence command" do
    {component, _server} = init_page(Campfire)
    component = put_page_state(component, :draft, "  ship it  ")

    component = Campfire.action(:send_message, %{}, component)

    assert component.state.draft == ""
    assert component.state.send_pending
    assert component.state.error == nil

    assert %Command{
             name: :persist_message,
             params: %{room_id: "room:general", body: "ship it", sender_id: "user:you"}
           } = component.next_command
  end

  test "send_message action accepts the submitted form body for Enter submits" do
    {component, _server} = init_page(Campfire)

    component = Campfire.action(:send_message, %{"body" => "  enter submit  "}, component)

    assert component.state.draft == ""
    assert component.state.send_pending

    assert %Command{
             name: :persist_message,
             params: %{room_id: "room:general", body: "enter submit", sender_id: "user:you"}
           } = component.next_command
  end

  test "run_agent_round action requires the safety cap" do
    {component, _server} = init_page(Campfire)
    component = put_page_state(component, :agent_safety_enabled, false)

    component = Campfire.action(:run_agent_round, %{}, component)

    assert component.state.agent_error == "Turn the safety cap back on before running agents."
    refute component.next_command
  end

  test "run_agent_round action queues a bounded server command" do
    {component, _server} = init_page(Campfire)

    component = Campfire.action(:run_agent_round, %{}, component)

    assert component.state.agent_round_pending
    assert component.state.agent_error == nil

    assert %Command{
             name: :run_agent_round,
             params: %{
               room_id: "room:general",
               safety_enabled: true,
               inter_agent_enabled: true
             }
           } = component.next_command
  end

  test "prompt_agent_round action validates blank prompts" do
    {component, _server} = init_page(Campfire)

    component = Campfire.action(:prompt_agent_round, %{"agent_prompt" => "   "}, component)

    assert component.state.agent_error == "Ask a question first."
    refute component.next_command
  end

  test "prompt_agent_round action saves a prompt and queues an agent round" do
    {component, _server} = init_page(Campfire)
    component = put_page_state(component, :agent_prompt_draft, "  How should we ship this?  ")

    component = Campfire.action(:prompt_agent_round, %{}, component)

    assert component.state.agent_prompt_draft == ""
    assert component.state.agent_round_pending
    assert component.state.agent_error == nil

    assert %Command{
             name: :prompt_agent_round,
             params: %{
               room_id: "room:general",
               body: "How should we ship this?",
               sender_id: "user:you",
               safety_enabled: true,
               inter_agent_enabled: true
             }
           } = component.next_command
  end

  test "persist_message command writes through jido_messaging and broadcasts a Hologram action" do
    body = "hologram command test #{System.unique_integer([:positive])}"
    server = %Server{cid: "page", instance_id: "command-test", session_id: "session-test"}

    server =
      Campfire.command(:persist_message, %{room_id: "room:general", body: body}, server)

    assert [
             %Broadcast{
               channel: {:workspace, "jido"},
               action_name: :message_saved,
               params: %{
                 room_id: "room:general",
                 message: message,
                 signal: %{type: "jido.messaging.room.message_added"}
               }
             }
           ] = server.broadcasts

    assert message.body == body
    assert message.own
  end

  test "message_saved action updates inactive room state and unread count" do
    {component, _server} = init_page(Campfire)
    message = message_view("room:runtime")

    component =
      Campfire.action(:message_saved, %{room_id: "room:runtime", message: message}, component)

    assert Enum.any?(component.state.messages_by_room["room:runtime"], &(&1.id == message.id))
    assert Enum.find(component.state.rooms, &(&1.id == "room:runtime")).unread == 1
    assert component.state.last_event.title == "Message stored"
    assert component.state.last_event.layer == "Jido Signal"
    refute Enum.any?(component.state.messages, &(&1.id == message.id))
  end

  test "select_room action switches rooms and clears unread count" do
    {component, _server} = init_page(Campfire)
    message = message_view("room:runtime")

    component =
      Campfire.action(:message_saved, %{room_id: "room:runtime", message: message}, component)

    component = Campfire.action(:select_room, %{id: "room:runtime"}, component)

    assert component.state.active_room_id == "room:runtime"
    assert Enum.find(component.state.rooms, &(&1.id == "room:runtime")).unread == 0
    assert Enum.any?(component.state.messages, &(&1.id == message.id))

    assert Enum.any?(
             component.state.developer_room_metrics,
             &(&1 == %{label: "Room", value: "#runtime"})
           )

    assert component.state.last_event.title == "Room selected"
  end

  test "open_thread action exposes a mobile thread dialog" do
    {component, _server} = init_page(Campfire)
    root = List.first(component.state.messages)

    component = Campfire.action(:open_thread, %{message_id: root.id}, component)

    assert component.state.thread_open
    assert component.state.thread_root.id == root.id
    assert component.state.last_event.title == "Thread opened"

    dom = ThreadPanel.template().(component.state)
    assert dom_has_attr?(dom, "role", "dialog")
    assert dom_has_class_fragment?(dom, "xl:hidden")
  end

  test "send_reply action accepts the submitted form body for Enter submits" do
    {component, _server} = init_page(Campfire)
    root = List.first(component.state.messages)

    component = Campfire.action(:open_thread, %{message_id: root.id}, component)
    component = Campfire.action(:send_reply, %{"reply" => "  thread note  "}, component)

    assert component.state.reply_draft == ""
    assert component.state.reply_pending

    assert %Command{
             name: :persist_reply,
             params: %{
               room_id: "room:general",
               root_message_id: root_id,
               body: "thread note",
               sender_id: "user:you"
             }
           } = component.next_command

    assert root_id == root.id
  end

  test "rail buttons switch to channel and direct-message groups" do
    {component, _server} = init_page(Campfire)

    component = Campfire.action(:rail_direct_messages, %{}, component)
    assert component.state.rail_target == "direct_messages"
    assert component.state.active_room_kind == "dm"
    assert component.state.active_room_id == "dm:maggie"

    component = Campfire.action(:rail_channels, %{}, component)
    assert component.state.rail_target == "channels"
    assert component.state.active_room_kind == "channel"
    assert component.state.active_room_id == "room:general"
  end

  test "rail search and user buttons expose their active targets" do
    {component, _server} = init_page(Campfire)

    component = Campfire.action(:rail_search, %{}, component)
    assert component.state.rail_target == "search"
    assert component.state.active_room_id == "room:general"

    component = Campfire.action(:rail_users, %{}, component)
    assert component.state.rail_target == "users"
    assert component.state.active_room_id == "room:general"
  end

  test "persist_channel command creates a group chat and broadcasts it" do
    name = "hologram-test-#{System.unique_integer([:positive])}"
    server = %Server{cid: "page", instance_id: "channel-test", session_id: "session-test"}

    server = Campfire.command(:persist_channel, %{name: name, topic: "Testing Hologram"}, server)

    assert [
             %Broadcast{
               channel: {:workspace, "jido"},
               action_name: :room_created,
               params: %{
                 room: room,
                 messages: [message],
                 signal: %{type: "jido.messaging.room.created"}
               }
             }
           ] = server.broadcasts

    assert room.kind == "channel"
    assert room.name == name
    assert message.room_id == room.id
  end

  test "room_created action adds the room to page state and resets the form" do
    {component, _server} = init_page(Campfire)

    room = %{
      id: "room:test-created",
      name: "test-created",
      kind: "channel",
      prefix: "#",
      topic: "Created during action test.",
      unread: 0,
      online: nil,
      presence: "active",
      avatar: "#",
      tone: "bg-[var(--campfire-accent)] text-stone-950",
      member_count: 1,
      member_count_label: "1 member",
      position: 1
    }

    message = message_view(room.id)

    component =
      component
      |> put_page_state(:room_form_open, true)
      |> put_page_state(:new_room_name, "test-created")
      |> put_page_state(:new_room_topic, "Created during action test.")
      |> put_page_state(:new_room_pending, true)

    component = Campfire.action(:room_created, %{room: room, messages: [message]}, component)

    assert Enum.any?(component.state.channels, &(&1.id == room.id))
    assert component.state.messages_by_room[room.id] == [message]
    assert Map.has_key?(component.state.developer_contract_by_room, room.id)
    assert component.state.last_event.title == "Room created"
    assert component.state.last_event.layer == "Jido Signal"
    refute component.state.room_form_open
    assert component.state.new_room_name == ""
    assert component.state.new_room_topic == ""
    refute component.state.new_room_pending
  end

  test "agent_round_finished action stores agent messages in the active timeline" do
    {component, _server} = init_page(Campfire)

    messages = [
      message_view("room:general",
        sender_id: "agent:alice",
        author: "Alice",
        avatar: "AL",
        tone: "bg-cyan-200 text-cyan-950"
      )
    ]

    component = put_page_state(component, :agent_round_pending, true)

    component =
      Campfire.action(
        :agent_round_finished,
        %{
          room_id: "room:general",
          messages: messages,
          agent_demo: component.state.agent_demo,
          signal: %{type: "jido.messaging.room.message_added"}
        },
        component
      )

    refute component.state.agent_round_pending
    assert component.state.agent_error == nil
    assert Enum.any?(component.state.messages, &(&1.id == List.first(messages).id))
    assert component.state.last_event.title == "Agent round stored"
    assert component.state.last_event.layer == "Jido AI + Jido Messaging"
  end

  defp message_view(room_id, overrides \\ []) do
    defaults = %{
      sender_id: "user:maggie",
      author: "Maggie",
      avatar: "MH",
      tone: "bg-rose-200 text-rose-950"
    }

    profile = Map.merge(defaults, Map.new(overrides))

    %{
      id: "message:#{room_id}:#{System.unique_integer([:positive])}",
      room_id: room_id,
      sender_id: profile.sender_id,
      author: profile.author,
      avatar: profile.avatar,
      tone: profile.tone,
      own: false,
      time: "07:20",
      body: "A test message.",
      status: "sent",
      thread_id: nil,
      reply_to_id: nil,
      is_reply: false,
      reply_count: 0,
      mentioned_user_ids: [],
      mentions_current_user: false,
      reactions: [],
      available_reactions: Chat.reaction_options()
    }
  end

  defp dom_has_attr?(nodes, name, value) when is_list(nodes) do
    Enum.any?(nodes, &dom_has_attr?(&1, name, value))
  end

  defp dom_has_attr?({:element, _tag, attrs, children}, name, value) do
    Enum.any?(attrs, fn
      {^name, attr_value} -> attr_value_equals?(attr_value, value)
      _other -> false
    end) || dom_has_attr?(children, name, value)
  end

  defp dom_has_attr?(_node, _name, _value), do: false

  defp dom_has_class_fragment?(nodes, fragment) when is_list(nodes) do
    Enum.any?(nodes, &dom_has_class_fragment?(&1, fragment))
  end

  defp dom_has_class_fragment?({:element, _tag, attrs, children}, fragment) do
    class_match? =
      Enum.any?(attrs, fn
        {"class", class} -> attr_value_contains?(class, fragment)
        _other -> false
      end)

    class_match? || dom_has_class_fragment?(children, fragment)
  end

  defp dom_has_class_fragment?(_node, _fragment), do: false

  defp attr_value_equals?(value, expected) when is_list(value) do
    Enum.any?(value, fn
      {:text, text} -> text == expected
      _other -> false
    end)
  end

  defp attr_value_equals?(value, expected), do: value == expected

  defp attr_value_contains?(value, fragment) when is_list(value) do
    Enum.any?(value, fn
      {:text, text} -> String.contains?(text, fragment)
      {:expression, text} when is_binary(text) -> String.contains?(text, fragment)
      _other -> false
    end)
  end

  defp attr_value_contains?(value, fragment) when is_binary(value) do
    String.contains?(value, fragment)
  end

  defp attr_value_contains?(_value, _fragment), do: false
end
