defmodule Jido.Campfire.AgentsTest do
  use ExUnit.Case, async: false

  alias Jido.Campfire.{Agents, Chat, Messaging}

  setup do
    app_key = Application.get_env(:req_llm, :anthropic_api_key)
    env_key = System.get_env("ANTHROPIC_API_KEY")

    Application.delete_env(:req_llm, :anthropic_api_key)
    System.delete_env("ANTHROPIC_API_KEY")

    on_exit(fn ->
      restore_app_key(app_key)
      restore_env_key(env_key)
    end)

    :ok
  end

  test "snapshot exposes the three seeded Jido AI participants" do
    snapshot = Agents.snapshot()

    assert Enum.map(snapshot.agents, & &1.name) == ["Alice", "Bob", "Charlie"]
    assert snapshot.model == "anthropic:claude-haiku-4-5"
    assert snapshot.safety.max_agents_per_round == 3
    assert snapshot.missing_api_key
  end

  test "run_round refuses to run without an Anthropic API key" do
    assert {:error, :missing_api_key} = Agents.run_round("room:agent-lab")
  end

  test "run_round requires the safety cap even with a test responder" do
    assert {:error, :safety_required} =
             Agents.run_round("room:agent-lab",
               safety_enabled: false,
               responder: fn agent, _room, _transcript -> {:ok, "#{agent.name} ready."} end
             )
  end

  test "run_round writes bounded agent replies through the Campfire chat context" do
    responder = fn agent, _room, transcript ->
      {:ok,
       "#{agent.name} sees #{Enum.count(transcript)} prior messages and adds one bounded reply."}
    end

    assert {:ok, result} =
             Agents.run_round("room:agent-lab",
               responder: responder,
               safety_enabled: true,
               inter_agent_enabled: true
             )

    assert Enum.map(result.messages, & &1.author) == ["Alice", "Bob", "Charlie"]
    assert Enum.count(result.signals) == 3

    for message <- result.messages do
      assert message.room_id == "room:agent-lab"
      assert message.sender_id in ["agent:alice", "agent:bob", "agent:charlie"]

      assert {:ok, persisted} = Messaging.get_message(message.id)
      assert persisted.role == :assistant
      assert persisted.metadata.source == "jido_ai"
      assert is_binary(persisted.metadata.agent_round_id)
    end

    assert Enum.any?(
             Chat.list_message_views("room:agent-lab"),
             &(&1.id == List.last(result.messages).id)
           )
  end

  test "run_round can keep agent turns out of later agent context" do
    parent = self()

    responder = fn agent, _room, transcript ->
      send(parent, {:agent_transcript, agent.name, Enum.count(transcript)})
      {:ok, "#{agent.name} replies without using the other agent turns."}
    end

    assert {:ok, result} =
             Agents.run_round("room:agent-lab",
               responder: responder,
               safety_enabled: true,
               inter_agent_enabled: false
             )

    assert Enum.count(result.messages) == 3

    assert_receive {:agent_transcript, "Alice", count}
    assert_receive {:agent_transcript, "Bob", ^count}
    assert_receive {:agent_transcript, "Charlie", ^count}
  end

  defp restore_app_key(nil), do: Application.delete_env(:req_llm, :anthropic_api_key)
  defp restore_app_key(value), do: Application.put_env(:req_llm, :anthropic_api_key, value)

  defp restore_env_key(nil), do: System.delete_env("ANTHROPIC_API_KEY")
  defp restore_env_key(value), do: System.put_env("ANTHROPIC_API_KEY", value)
end
