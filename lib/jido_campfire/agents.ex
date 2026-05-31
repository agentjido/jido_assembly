defmodule Jido.Campfire.Agents do
  @moduledoc """
  On-demand Jido AI agent orchestration for the Campfire developer demo.

  The agents are ordinary Campfire participants. A bounded round starts one
  short-lived `Jido.AI.Agent` runtime per persona, asks for one chat-sized
  response, then writes the response through `Jido.Campfire.Chat` so SQLite,
  Jido Messaging signals, Hologram broadcasts, mentions, and reactions all use
  the same path as human messages.
  """

  alias Jido.Campfire.{Chat, Messaging, Seeds}

  @model :campfire_haiku
  @max_agents_per_round 3
  @max_reply_chars 700
  @recent_message_count 18
  @default_timeout_ms 30_000

  @agent_modules %{
    "agent:alice" => Jido.Campfire.Agents.Alice,
    "agent:bob" => Jido.Campfire.Agents.Bob,
    "agent:charlie" => Jido.Campfire.Agents.Charlie
  }

  def all do
    Enum.map(Seeds.agent_people(), fn person ->
      person
      |> Map.take([:id, :name, :handle, :initials, :title, :tone])
      |> Map.put(:module, Map.fetch!(@agent_modules, person.id))
    end)
  end

  def snapshot do
    %{
      agents: Enum.map(all(), &agent_view/1),
      enabled: api_key_present?(),
      model: model_label(),
      safety: %{
        max_agents_per_round: @max_agents_per_round,
        max_reply_chars: @max_reply_chars,
        recent_message_count: @recent_message_count
      },
      missing_api_key: !api_key_present?()
    }
  end

  def run_round(room_id, opts \\ []) when is_binary(room_id) do
    opts = normalize_opts(opts)
    round_id = "agent-round:#{System.unique_integer([:positive])}"

    max_agents =
      opts |> Keyword.get(:max_agents, @max_agents_per_round) |> clamp(1, @max_agents_per_round)

    agents = all() |> Enum.take(max_agents)

    cond do
      Keyword.get(opts, :safety_enabled, true) != true ->
        {:error, :safety_required}

      !responder?(opts) && !api_key_present?() ->
        {:error, :missing_api_key}

      true ->
        with {:ok, room} <- Messaging.get_room(room_id) do
          transcript = transcript_for(room.id)

          inter_agent_enabled = Keyword.get(opts, :inter_agent_enabled, true)

          agents
          |> Enum.reduce_while({:ok, [], [], transcript}, fn agent,
                                                             {:ok, messages, signals, transcript} ->
            case agent_turn(agent, room, transcript, round_id, opts) do
              {:ok, message, turn_signals, next_line} ->
                next_transcript =
                  if inter_agent_enabled do
                    transcript ++ [next_line]
                  else
                    transcript
                  end

                {:cont, {:ok, messages ++ [message], signals ++ turn_signals, next_transcript}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end)
          |> case do
            {:ok, messages, signals, _transcript} ->
              {:ok,
               %{
                 room_id: room.id,
                 round_id: round_id,
                 agents: Enum.map(agents, &agent_view/1),
                 messages: messages,
                 signals: signals
               }}

            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  end

  def error_to_string(:missing_api_key), do: "Add ANTHROPIC_API_KEY before running AI agents."
  def error_to_string(:safety_required), do: "Turn the safety cap back on before running agents."
  def error_to_string(:empty_agent_reply), do: "The agent returned an empty reply."
  def error_to_string({:agent_failed, name, reason}), do: "#{name} failed: #{inspect(reason)}"
  def error_to_string(reason), do: "Agent round failed: #{inspect(reason)}"

  defp agent_turn(agent, room, transcript, round_id, opts) do
    prompt = prompt_for(agent, room, transcript, opts)

    with {:ok, reply} <- generate_reply(agent, room, transcript, prompt, opts),
         {:ok, reply} <- normalize_reply(reply, agent.name),
         {:ok, message, signals} <-
           Chat.send_message_command(room.id, reply, agent.id,
             role: :assistant,
             metadata: %{
               source: "jido_ai",
               agent_id: agent.id,
               agent_name: agent.name,
               agent_round_id: round_id,
               model: model_label()
             }
           ) do
      {:ok, message, signals,
       %{author: agent.name, body: reply, sender_id: agent.id, agent: true}}
    else
      {:error, reason} -> {:error, {:agent_failed, agent.name, reason}}
    end
  end

  defp generate_reply(agent, room, transcript, prompt, opts) do
    case Keyword.get(opts, :responder) do
      nil ->
        ask_agent(agent, prompt, opts)

      responder when is_function(responder, 4) ->
        responder.(agent, room, transcript, opts)

      responder when is_function(responder, 3) ->
        responder.(agent, room, transcript)
    end
  end

  defp ask_agent(agent, prompt, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    agent_id = "#{agent.id}:#{System.unique_integer([:positive])}"

    with {:ok, pid} <- Jido.Campfire.Jido.start_agent(agent.module, id: agent_id) do
      try do
        agent.module.ask_sync(pid, prompt,
          timeout: timeout,
          max_iterations: 2,
          llm_opts: [
            temperature: 0.45,
            max_tokens: 220,
            receive_timeout: timeout
          ]
        )
      after
        _ = Jido.Campfire.Jido.stop_agent(pid)
      end
    end
  end

  defp prompt_for(agent, room, transcript, opts) do
    inter_agent_enabled = Keyword.get(opts, :inter_agent_enabled, true)

    visible_transcript =
      if inter_agent_enabled do
        transcript
      else
        Enum.reject(transcript, &Map.get(&1, :agent, false))
      end

    transcript_text =
      visible_transcript
      |> Enum.take(-@recent_message_count)
      |> Enum.map_join("\n", fn line -> "#{line.author}: #{line.body}" end)
      |> blank_to_default("No prior messages in this room.")

    peer_instruction =
      if inter_agent_enabled do
        "The other AI agents may reply after you, so respond to the latest point and hand off cleanly."
      else
        "Respond to the human conversation only. Do not invite another agent to continue."
      end

    """
    Campfire room: #{room.name}
    Agent: #{agent.name} (#{agent.title})

    Recent transcript, oldest to newest:
    #{transcript_text}

    Write #{agent.name}'s next message.
    #{peer_instruction}
    One message only. No markdown table. No preamble. Stay under 90 words.
    """
  end

  defp transcript_for(room_id) do
    room_id
    |> Chat.list_message_views()
    |> Enum.take(-@recent_message_count)
    |> Enum.map(fn message ->
      %{
        author: message.author,
        body: compact_text(message.body),
        sender_id: message.sender_id,
        agent: String.starts_with?(message.sender_id, "agent:")
      }
    end)
  end

  defp normalize_reply({:ok, reply}, agent_name), do: normalize_reply(reply, agent_name)
  defp normalize_reply({:error, reason}, _agent_name), do: {:error, reason}

  defp normalize_reply(reply, agent_name) do
    reply =
      reply
      |> extract_text()
      |> compact_text()
      |> strip_speaker_prefix(agent_name)
      |> truncate_text(@max_reply_chars)

    if reply == "" do
      {:error, :empty_agent_reply}
    else
      {:ok, reply}
    end
  end

  defp extract_text(value) when is_binary(value), do: value
  defp extract_text(%{text: text}) when is_binary(text), do: text
  defp extract_text(%{"text" => text}) when is_binary(text), do: text

  defp extract_text(value) do
    if Code.ensure_loaded?(Jido.AI.Turn) and function_exported?(Jido.AI.Turn, :extract_text, 1) do
      Jido.AI.Turn.extract_text(value)
    else
      inspect(value)
    end
  rescue
    _error -> inspect(value)
  end

  defp compact_text(value) do
    value
    |> to_string()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp strip_speaker_prefix(text, agent_name) do
    Regex.replace(~r/^#{Regex.escape(agent_name)}\s*:\s*/i, text, "")
  end

  defp truncate_text(text, max_chars) do
    if String.length(text) <= max_chars do
      text
    else
      text |> String.slice(0, max_chars) |> String.trim_trailing() |> Kernel.<>("...")
    end
  end

  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value

  defp agent_view(agent) do
    %{
      id: agent.id,
      name: agent.name,
      handle: agent.handle,
      initials: agent.initials,
      title: agent.title,
      tone: agent.tone
    }
  end

  defp model_label do
    Jido.AI.model_label(@model)
  rescue
    _error -> "anthropic:claude-haiku-4-5"
  end

  defp api_key_present? do
    present?(ReqLLM.get_key(:anthropic_api_key)) or present?(ReqLLM.get_key("ANTHROPIC_API_KEY"))
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp responder?(opts), do: Keyword.has_key?(opts, :responder)

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(_opts), do: []

  defp clamp(value, min, max) when is_integer(value),
    do: value |> Kernel.max(min) |> Kernel.min(max)

  defp clamp(_value, _min, max), do: max
end
