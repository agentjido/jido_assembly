defmodule Jido.Campfire.Pages.Campfire do
  use Hologram.Page

  alias Jido.Campfire.Chat
  alias Jido.Campfire.Layouts.App

  route "/"

  layout App

  def init(_params, component, server) do
    snapshot = Chat.snapshot()

    component =
      put_state(component,
        workspace: snapshot.workspace,
        current_user: snapshot.current_user,
        rooms: snapshot.rooms,
        channels: snapshot.channels,
        direct_messages: snapshot.direct_messages,
        messages_by_room: snapshot.messages_by_room,
        active_room: snapshot.active_room,
        active_room_id: snapshot.active_room_id,
        active_room_name: snapshot.active_room_name,
        active_room_kind: snapshot.active_room_kind,
        active_room_prefix: snapshot.active_room_prefix,
        active_topic: snapshot.active_topic,
        member_count_label: snapshot.member_count_label,
        messages: snapshot.messages,
        message_count: Enum.count(snapshot.messages),
        draft: "",
        send_pending: false,
        error: nil,
        room_form_open: false,
        new_room_name: "",
        new_room_topic: "",
        new_room_pending: false,
        new_room_error: nil
      )

    server = put_subscription(server, {:workspace, Chat.workspace_id()})

    {component, server}
  end

  def action(:select_room, params, component) do
    select_room(component, params.id)
  end

  def action(:draft_changed, params, component) do
    put_state(component, :draft, params.event.value)
  end

  def action(:send_message, _params, component) do
    draft = String.trim(component.state.draft)

    if draft == "" do
      put_state(component, :error, "Type a message first.")
    else
      component
      |> put_state(:draft, "")
      |> put_state(:send_pending, true)
      |> put_state(:error, nil)
      |> put_command(:persist_message,
        room_id: component.state.active_room_id,
        body: draft
      )
    end
  end

  def action(:message_saved, params, component) do
    room_id = params.room_id
    message = params.message
    messages_for_room = Map.get(component.state.messages_by_room, room_id, [])

    messages_for_room =
      if Enum.any?(messages_for_room, &(&1.id == message.id)) do
        messages_for_room
      else
        messages_for_room ++ [message]
      end

    messages_by_room = Map.put(component.state.messages_by_room, room_id, messages_for_room)
    rooms = touch_room(component.state.rooms, room_id, component.state.active_room_id)
    component = put_rooms(component, rooms)

    component
    |> put_state(:messages_by_room, messages_by_room)
    |> put_state(:messages, active_messages(component, room_id, messages_for_room))
    |> put_state(:message_count, active_message_count(component, room_id, messages_for_room))
    |> put_state(:send_pending, false)
    |> put_state(:error, nil)
  end

  def action(:send_failed, params, component) do
    component
    |> put_state(:send_pending, false)
    |> put_state(:error, params.error)
  end

  def action(:toggle_room_form, _params, component) do
    put_state(component, :room_form_open, !component.state.room_form_open)
  end

  def action(:new_room_name_changed, params, component) do
    put_state(component, :new_room_name, params.event.value)
  end

  def action(:new_room_topic_changed, params, component) do
    put_state(component, :new_room_topic, params.event.value)
  end

  def action(:create_channel, _params, component) do
    name = String.trim(component.state.new_room_name)

    if name == "" do
      put_state(component, :new_room_error, "Name the group chat first.")
    else
      component
      |> put_state(:new_room_pending, true)
      |> put_state(:new_room_error, nil)
      |> put_command(:persist_channel,
        name: name,
        topic: component.state.new_room_topic
      )
    end
  end

  def action(:room_created, params, component) do
    room = params.room
    messages = params.messages || []
    rooms = upsert_room(component.state.rooms, room)
    messages_by_room = Map.put(component.state.messages_by_room, room.id, messages)

    component
    |> put_rooms(rooms)
    |> put_state(:messages_by_room, messages_by_room)
    |> put_state(:room_form_open, false)
    |> put_state(:new_room_name, "")
    |> put_state(:new_room_topic, "")
    |> put_state(:new_room_pending, false)
    |> put_state(:new_room_error, nil)
  end

  def action(:room_create_failed, params, component) do
    component
    |> put_state(:new_room_pending, false)
    |> put_state(:new_room_error, params.error)
  end

  def command(:persist_message, params, server) do
    case Chat.send_message(params.room_id, params.body) do
      {:ok, message} ->
        put_broadcast(server, {:workspace, Chat.workspace_id()}, :message_saved,
          room_id: message.room_id,
          message: message
        )

      {:error, reason} ->
        put_action(server, :send_failed, error: Chat.error_to_string(reason))
    end
  end

  def command(:persist_channel, params, server) do
    case Chat.create_channel(%{name: params.name, topic: params.topic}) do
      {:ok, room, messages} ->
        put_broadcast(server, {:workspace, Chat.workspace_id()}, :room_created,
          room: room,
          messages: messages
        )

      {:error, reason} ->
        put_action(server, :room_create_failed, error: Chat.error_to_string(reason))
    end
  end

  def template do
    ~HOLO"""
    <main class="h-screen min-h-[640px] bg-[var(--campfire-bg)] text-[var(--campfire-ink)]">
      <div class="grid h-full grid-cols-[minmax(0,1fr)] overflow-hidden md:grid-cols-[72px_290px_minmax(0,1fr)] xl:grid-cols-[72px_290px_minmax(0,1fr)_320px]">
        <aside class="hidden flex-col items-center gap-3 border-r border-white/8 bg-[var(--campfire-rail)] px-3 py-4 text-stone-200 md:flex">
          <div class="grid size-11 place-items-center rounded-lg bg-[var(--campfire-accent)] text-base font-black text-stone-950 shadow-sm">
            JC
          </div>
          <button class="grid size-10 place-items-center rounded-md bg-white/8 text-stone-200 transition hover:bg-white/12" type="button" title="Channels">
            <span class="hero-chat-bubble-left-right size-5"></span>
          </button>
          <button class="grid size-10 place-items-center rounded-md bg-white/8 text-stone-200 transition hover:bg-white/12" type="button" title="Direct messages">
            <span class="hero-at-symbol size-5"></span>
          </button>
          <button class="grid size-10 place-items-center rounded-md bg-white/8 text-stone-200 transition hover:bg-white/12" type="button" title="Search">
            <span class="hero-magnifying-glass size-5"></span>
          </button>
          <div class="mt-auto grid size-10 place-items-center rounded-md border border-white/10 bg-white/6 text-xs font-semibold text-stone-300">
            {@current_user.initials}
          </div>
        </aside>

        <aside class="hidden min-h-0 flex-col bg-[var(--campfire-sidebar)] text-stone-100 md:flex">
          <header class="border-b border-white/8 px-5 py-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-semibold text-stone-400">Workspace</p>
                <h1 class="mt-1 text-lg font-bold text-stone-50">{@workspace.name}</h1>
              </div>
              <span class="rounded-md bg-[var(--campfire-green)]/18 px-2 py-1 text-xs font-semibold text-emerald-200">live</span>
            </div>
          </header>

          <div class="min-h-0 flex-1 overflow-y-auto px-3 py-4">
            <section>
              <div class="mb-2 flex items-center justify-between px-2 text-xs font-semibold text-stone-400">
                <span>Group chats</span>
                <button class="grid size-7 place-items-center rounded-md text-stone-300 transition hover:bg-white/8" type="button" title="New group chat" $click="toggle_room_form">
                  <span class="hero-plus size-4"></span>
                </button>
              </div>

              {%if @room_form_open}
                <form class="mb-3 space-y-2 rounded-lg border border-white/10 bg-white/6 p-2" $submit="create_channel">
                  <input
                    class="h-9 w-full rounded-md border border-white/10 bg-stone-950/30 px-3 text-sm text-stone-100 outline-none placeholder:text-stone-500"
                    name="name"
                    placeholder="group-chat"
                    value={@new_room_name}
                    $change="new_room_name_changed"
                  />
                  <input
                    class="h-9 w-full rounded-md border border-white/10 bg-stone-950/30 px-3 text-sm text-stone-100 outline-none placeholder:text-stone-500"
                    name="topic"
                    placeholder="Topic"
                    value={@new_room_topic}
                    $change="new_room_topic_changed"
                  />
                  {%if @new_room_error}
                    <p class="text-xs text-amber-200">{@new_room_error}</p>
                  {/if}
                  <button class="inline-flex h-8 w-full items-center justify-center gap-2 rounded-md bg-[var(--campfire-accent)] px-3 text-sm font-bold text-stone-950 transition hover:bg-[var(--campfire-accent-strong)] hover:text-stone-100 disabled:opacity-60" type="submit" disabled={@new_room_pending}>
                    <span class="hero-user-group size-4"></span>
                    {%if @new_room_pending}Creating{%else}Create chat{/if}
                  </button>
                </form>
              {/if}

              <div class="space-y-1">
                {%for channel <- @channels}
                  <button
                    class="flex w-full items-center justify-between rounded-md px-2.5 py-2 text-left text-sm transition {if channel.id == @active_room_id do "bg-white/12 text-stone-50" else "text-stone-300 hover:bg-white/8 hover:text-stone-50" end}"
                    type="button"
                    $click={:select_room, id: channel.id}
                  >
                    <span class="min-w-0 truncate"># {channel.name}</span>
                    {%if channel.unread > 0}
                      <span class="ml-3 rounded-full bg-[var(--campfire-accent)] px-2 py-0.5 text-xs font-bold text-stone-950">{channel.unread}</span>
                    {/if}
                  </button>
                {/for}
              </div>
            </section>

            <section class="mt-6">
              <div class="mb-2 px-2 text-xs font-semibold text-stone-400">
                Direct messages
              </div>
              <div class="space-y-1">
                {%for person <- @direct_messages}
                  <button
                    class="flex w-full items-center justify-between rounded-md px-2.5 py-2 text-left text-sm transition {if person.id == @active_room_id do "bg-white/12 text-stone-50" else "text-stone-300 hover:bg-white/8 hover:text-stone-50" end}"
                    type="button"
                    $click={:select_room, id: person.id}
                  >
                    <span class="flex min-w-0 items-center gap-2">
                      <span class="size-2 rounded-full {if person.online do "bg-[var(--campfire-green)]" else "bg-stone-500" end}"></span>
                      <span class="truncate">{person.name}</span>
                    </span>
                    {%if person.unread > 0}
                      <span class="ml-3 rounded-full bg-[var(--campfire-accent)] px-2 py-0.5 text-xs font-bold text-stone-950">{person.unread}</span>
                    {/if}
                  </button>
                {/for}
              </div>
            </section>
          </div>
        </aside>

        <section class="flex min-h-0 flex-col bg-[var(--campfire-panel)]">
          <header class="border-b border-[var(--campfire-line)] px-4 py-3 sm:px-6">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div class="min-w-0">
                <p class="mb-1 text-xs font-semibold text-[var(--campfire-muted)] md:hidden">{@workspace.name}</p>
                <div class="flex items-center gap-3">
                  <h2 class="truncate text-xl font-bold text-[var(--campfire-ink)]">{@active_room_prefix} {@active_room_name}</h2>
                  <span class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] px-2 py-1 text-xs font-semibold text-[var(--campfire-muted)]">
                    {@member_count_label}
                  </span>
                </div>
                <p class="mt-1 max-w-[70ch] truncate text-sm text-[var(--campfire-muted)]">{@active_topic}</p>
              </div>
              <div class="flex items-center gap-2">
                <button class="hidden rounded-md border border-[var(--campfire-line)] bg-transparent px-3 py-2 text-sm font-semibold text-[var(--campfire-muted)] transition hover:bg-[var(--campfire-panel-muted)] sm:inline-flex" type="button">
                  Threads
                </button>
                <button class="rounded-md bg-[var(--campfire-ink)] px-3 py-2 text-sm font-semibold text-stone-100 transition hover:bg-stone-800" type="button">
                  Invite
                </button>
              </div>
            </div>

            <div class="mt-3 flex gap-2 overflow-x-auto pb-1 md:hidden">
              {%for room <- @rooms}
                <button
                  class="shrink-0 rounded-md border px-3 py-1.5 text-sm font-semibold transition {if room.id == @active_room_id do "border-[var(--campfire-accent)] bg-[var(--campfire-accent)] text-stone-950" else "border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] text-[var(--campfire-muted)]" end}"
                  type="button"
                  $click={:select_room, id: room.id}
                >
                  {room.prefix}{room.name}
                </button>
              {/for}
            </div>
          </header>

          <div class="min-h-0 flex-1 overflow-y-auto px-4 py-5 sm:px-6">
            <div class="mx-auto max-w-4xl space-y-5">
              <div class="rounded-lg border border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] px-4 py-3 text-sm text-[var(--campfire-muted)]">
                Messages in this room are persisted through jido_messaging and pushed live with Hologram realtime.
              </div>

              {%for message <- @messages}
                <article class="group flex gap-3">
                  <div class="grid size-10 shrink-0 place-items-center rounded-lg {message.tone} text-sm font-black">
                    {message.avatar}
                  </div>
                  <div class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-baseline gap-2">
                      <h3 class="text-sm font-bold text-[var(--campfire-ink)]">{message.author}</h3>
                      <time class="text-xs text-[var(--campfire-muted)]">{message.time}</time>
                      {%if message.own}
                        <span class="rounded-full bg-[var(--campfire-accent)]/20 px-2 py-0.5 text-xs font-semibold text-[var(--campfire-accent-strong)]">{message.status}</span>
                      {/if}
                    </div>
                    <p class="mt-1 max-w-[74ch] text-sm leading-6 text-stone-700">{message.body}</p>
                  </div>
                </article>
              {/for}
            </div>
          </div>

          <footer class="border-t border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-4 py-4 sm:px-6">
            <form class="mx-auto flex max-w-4xl items-end gap-3 rounded-lg border border-[var(--campfire-line)] bg-stone-50 p-2 shadow-sm" $submit="send_message">
              <textarea
                class="min-h-11 flex-1 resize-none rounded-md bg-transparent px-3 py-2 text-sm leading-6 text-[var(--campfire-ink)] outline-none placeholder:text-stone-400"
                name="body"
                placeholder="Message {@active_room_prefix} {@active_room_name}"
                rows="1"
                value={@draft}
                $change="draft_changed"
              />
              <button class="inline-flex min-w-20 items-center justify-center gap-2 rounded-md bg-[var(--campfire-accent)] px-4 py-2.5 text-sm font-bold text-stone-950 transition hover:bg-[var(--campfire-accent-strong)] hover:text-stone-100 disabled:opacity-60" type="submit" disabled={@send_pending}>
                <span class="hero-paper-airplane size-4"></span>
                {%if @send_pending}Sending{%else}Send{/if}
              </button>
            </form>
            {%if @error}
              <p class="mx-auto mt-2 max-w-4xl text-sm font-semibold text-amber-700">{@error}</p>
            {/if}
          </footer>
        </section>

        <aside class="hidden min-h-0 flex-col border-l border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] xl:flex">
          <header class="border-b border-[var(--campfire-line)] px-5 py-4">
            <h2 class="text-sm font-bold text-[var(--campfire-ink)]">Room context</h2>
            <p class="mt-1 text-sm text-[var(--campfire-muted)]">{@active_room_prefix} {@active_room_name}</p>
          </header>
          <div class="space-y-5 overflow-y-auto p-5">
            <section>
              <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Conversation</h3>
              <div class="space-y-2">
                <div class="flex items-center justify-between rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-3 py-2 text-sm">
                  <span>Type</span>
                  <span class="font-semibold text-stone-700">{@active_room_kind}</span>
                </div>
                <div class="flex items-center justify-between rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-3 py-2 text-sm">
                  <span>Messages</span>
                  <span class="font-semibold text-stone-700">{@message_count}</span>
                </div>
                <div class="flex items-center justify-between rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-3 py-2 text-sm">
                  <span>Realtime</span>
                  <span class="text-xs font-semibold text-emerald-700">workspace broadcast</span>
                </div>
              </div>
            </section>

            <section>
              <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">jido_messaging</h3>
              <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-3">
                <p class="text-sm leading-6 text-stone-700">
                  Rooms, DMs, participants, and messages are canonical Jido.Messaging records. The UI holds only view state and unread counters.
                </p>
              </div>
            </section>

            <section>
              <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Next runtime work</h3>
              <ul class="space-y-2 text-sm leading-6 text-stone-700">
                <li>Swap ETS for durable persistence.</li>
                <li>Attach bridge rooms to Slack, Discord, or Mattermost adapters.</li>
                <li>Let Room Assistant subscribe to room message signals.</li>
              </ul>
            </section>
          </div>
        </aside>
      </div>
    </main>
    """
  end

  defp select_room(component, room_id) do
    room = Enum.find(component.state.rooms, &(&1.id == room_id)) || component.state.active_room
    messages = Map.get(component.state.messages_by_room, room.id, [])
    rooms = clear_unread(component.state.rooms, room.id)

    component
    |> put_rooms(rooms)
    |> put_state(:active_room, room)
    |> put_state(:active_room_id, room.id)
    |> put_state(:active_room_name, room.name)
    |> put_state(:active_room_kind, room.kind)
    |> put_state(:active_room_prefix, room.prefix)
    |> put_state(:active_topic, room.topic)
    |> put_state(:member_count_label, room.member_count_label)
    |> put_state(:messages, messages)
    |> put_state(:message_count, Enum.count(messages))
    |> put_state(:draft, "")
    |> put_state(:error, nil)
  end

  defp active_messages(component, room_id, messages_for_room) do
    if component.state.active_room_id == room_id do
      messages_for_room
    else
      component.state.messages
    end
  end

  defp active_message_count(component, room_id, messages_for_room) do
    if component.state.active_room_id == room_id do
      Enum.count(messages_for_room)
    else
      component.state.message_count
    end
  end

  defp touch_room(rooms, room_id, active_room_id) do
    Enum.map(rooms, fn room ->
      cond do
        room.id == room_id and room.id == active_room_id ->
          Map.put(room, :unread, 0)

        room.id == room_id ->
          Map.put(room, :unread, room.unread + 1)

        true ->
          room
      end
    end)
  end

  defp clear_unread(rooms, room_id) do
    Enum.map(rooms, fn room ->
      if room.id == room_id, do: Map.put(room, :unread, 0), else: room
    end)
  end

  defp upsert_room(rooms, new_room) do
    if Enum.any?(rooms, &(&1.id == new_room.id)) do
      Enum.map(rooms, fn room ->
        if room.id == new_room.id, do: new_room, else: room
      end)
    else
      rooms ++ [new_room]
    end
  end

  defp put_rooms(component, rooms) do
    component
    |> put_state(:rooms, rooms)
    |> put_state(:channels, Enum.filter(rooms, &(&1.kind == "channel")))
    |> put_state(:direct_messages, Enum.filter(rooms, &(&1.kind == "dm")))
  end
end
