defmodule Jido.Campfire.Pages.Campfire do
  use Hologram.Page

  alias Hologram.JS
  alias Jido.Campfire.Chat
  alias Jido.Campfire.Layouts.App

  route "/"

  layout App

  def init(_params, component, server) do
    component =
      component
      |> apply_snapshot(Chat.snapshot())
      |> put_state(
        draft: "",
        send_pending: false,
        error: nil,
        room_form_open: false,
        new_room_name: "",
        new_room_topic: "",
        new_room_pending: false,
        new_room_error: nil,
        search_query: "",
        search_results: [],
        thread_open: false,
        thread_root: nil,
        thread_messages: [],
        reply_draft: "",
        reply_pending: false,
        reply_error: nil,
        rail_target: "channels"
      )

    server = put_subscription(server, {:workspace, Chat.workspace_id()})

    {component, server}
  end

  def action(:select_room, params, component) do
    select_room(component, params.id)
  end

  def action(:rail_workspace, _params, component) do
    focus_rail_target(:workspace)
    select_room(component, "room:general")
  end

  def action(:rail_channels, _params, component) do
    focus_rail_target(:channels)

    component
    |> put_state(:rail_target, "channels")
    |> select_first_room(component.state.channels)
  end

  def action(:rail_direct_messages, _params, component) do
    focus_rail_target(:direct_messages)

    component
    |> put_state(:rail_target, "direct_messages")
    |> select_first_room(component.state.direct_messages)
  end

  def action(:rail_search, _params, component) do
    focus_rail_target(:search)
    put_state(component, :rail_target, "search")
  end

  def action(:rail_users, _params, component) do
    focus_rail_target(:users)
    put_state(component, :rail_target, "users")
  end

  def action(:select_user, params, component) do
    put_command(component, :load_snapshot,
      user_id: params.id,
      active_room_id: component.state.active_room_id
    )
  end

  def action(:snapshot_loaded, params, component) do
    component
    |> apply_snapshot(params.snapshot)
    |> put_state(:thread_open, false)
    |> put_state(:thread_root, nil)
    |> put_state(:thread_messages, [])
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
        body: draft,
        sender_id: component.state.current_user.id
      )
    end
  end

  def action(:reply_draft_changed, params, component) do
    put_state(component, :reply_draft, params.event.value)
  end

  def action(:send_reply, _params, component) do
    draft = String.trim(component.state.reply_draft)

    cond do
      !component.state.thread_root ->
        put_state(component, :reply_error, "Open a thread first.")

      draft == "" ->
        put_state(component, :reply_error, "Type a reply first.")

      true ->
        component
        |> put_state(:reply_draft, "")
        |> put_state(:reply_pending, true)
        |> put_state(:reply_error, nil)
        |> put_command(:persist_reply,
          room_id: component.state.active_room_id,
          root_message_id: component.state.thread_root.id,
          body: draft,
          sender_id: component.state.current_user.id
        )
    end
  end

  def action(:message_saved, params, component) do
    message = personalize_message(params.message, component.state.current_user.id)
    room_id = message.room_id

    component =
      if Map.get(message, :is_reply, false) do
        put_thread_reply(component, room_id, message)
      else
        put_timeline_message(component, room_id, message)
      end

    rooms =
      touch_room(
        component.state.rooms,
        room_id,
        component.state.active_room_id,
        message.own,
        message.mentions_current_user
      )

    component
    |> put_rooms(rooms)
    |> put_state(:send_pending, false)
    |> put_state(:reply_pending, false)
    |> put_state(:error, nil)
    |> put_state(:reply_error, nil)
    |> put_active_developer_context(
      developer_event(
        if(Map.get(message, :is_reply, false), do: "Reply stored", else: "Message stored"),
        "Jido Messaging broadcast",
        "#{message.author} in #{room_label(component, room_id)}"
      )
    )
  end

  def action(:send_failed, params, component) do
    component
    |> put_state(:send_pending, false)
    |> put_state(:reply_pending, false)
    |> put_state(:error, params.error)
  end

  def action(:toggle_reaction, params, component) do
    put_command(component, :persist_reaction,
      message_id: params.message_id,
      emoji: params.emoji,
      user_id: component.state.current_user.id
    )
  end

  def action(:reaction_saved, params, component) do
    message = personalize_message(params.message, component.state.current_user.id)

    component
    |> update_message_everywhere(message)
    |> put_active_developer_context(
      developer_event(
        "Reaction stored",
        "Jido Messaging update",
        "#{message.author} in #{room_label(component, message.room_id)}"
      )
    )
  end

  def action(:open_thread, params, component) do
    root = Enum.find(component.state.messages, &(&1.id == params.message_id))
    thread_messages = get_thread_messages(component, root && root.id)

    component
    |> put_state(:thread_open, true)
    |> put_state(:thread_root, root)
    |> put_state(:thread_messages, thread_messages)
    |> put_state(:reply_draft, "")
    |> put_state(:reply_error, nil)
    |> put_active_developer_context(
      developer_event(
        "Thread opened",
        "Hologram action",
        if(root, do: root.author, else: "missing message")
      )
    )
  end

  def action(:close_thread, _params, component) do
    component
    |> put_state(:thread_open, false)
    |> put_state(:thread_root, nil)
    |> put_state(:thread_messages, [])
    |> put_state(:reply_draft, "")
    |> put_state(:reply_error, nil)
    |> put_active_developer_context(
      developer_event("Thread closed", "Hologram action", component.state.active_room_name)
    )
  end

  def action(:search_changed, params, component) do
    query = params.event.value

    component =
      component
      |> put_state(:search_query, query)
      |> put_state(:search_results, [])

    if String.trim(query) == "" do
      component
    else
      put_command(component, :run_search,
        query: query,
        user_id: component.state.current_user.id
      )
    end
  end

  def action(:search_loaded, params, component) do
    put_state(component, :search_results, params.results)
  end

  def action(:select_search_result, params, component) do
    component = select_room(component, params.room_id)

    if params.thread_id do
      component =
        component
        |> put_state(:search_query, "")
        |> put_state(:search_results, [])

      action(:open_thread, %{message_id: params.thread_id}, component)
    else
      component
      |> put_state(:search_query, "")
      |> put_state(:search_results, [])
    end
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

    messages =
      Enum.map(params.messages || [], &personalize_message(&1, component.state.current_user.id))

    rooms = upsert_room(component.state.rooms, room)
    messages_by_room = Map.put(component.state.messages_by_room, room.id, messages)
    threads_by_room = Map.put(component.state.threads_by_room, room.id, %{})

    contracts_by_room =
      Map.put(
        component.state.developer_contract_by_room,
        room.id,
        fallback_developer_contract(room)
      )

    component
    |> put_rooms(rooms)
    |> put_state(:messages_by_room, messages_by_room)
    |> put_state(:threads_by_room, threads_by_room)
    |> put_state(:developer_contract_by_room, contracts_by_room)
    |> put_state(:room_form_open, false)
    |> put_state(:new_room_name, "")
    |> put_state(:new_room_topic, "")
    |> put_state(:new_room_pending, false)
    |> put_state(:new_room_error, nil)
    |> put_active_developer_context(
      developer_event("Room created", "Jido Messaging room", "#{room.prefix}#{room.name}")
    )
  end

  def action(:room_create_failed, params, component) do
    component
    |> put_state(:new_room_pending, false)
    |> put_state(:new_room_error, params.error)
  end

  def command(:load_snapshot, params, server) do
    put_action(server, :snapshot_loaded,
      snapshot: Chat.snapshot(params.user_id, params.active_room_id)
    )
  end

  def command(:persist_message, params, server) do
    case Chat.send_message(
           params.room_id,
           params.body,
           Map.get(params, :sender_id, Chat.current_user_id())
         ) do
      {:ok, message} ->
        put_broadcast(server, {:workspace, Chat.workspace_id()}, :message_saved,
          room_id: message.room_id,
          message: message
        )

      {:error, reason} ->
        put_action(server, :send_failed, error: Chat.error_to_string(reason))
    end
  end

  def command(:persist_reply, params, server) do
    case Chat.send_message(params.room_id, params.body, params.sender_id,
           thread_id: params.root_message_id,
           reply_to_id: params.root_message_id
         ) do
      {:ok, message} ->
        put_broadcast(server, {:workspace, Chat.workspace_id()}, :message_saved,
          room_id: message.room_id,
          message: message
        )

      {:error, reason} ->
        put_action(server, :send_failed, error: Chat.error_to_string(reason))
    end
  end

  def command(:persist_reaction, params, server) do
    case Chat.toggle_reaction(params.message_id, params.emoji, params.user_id) do
      {:ok, message} ->
        put_broadcast(server, {:workspace, Chat.workspace_id()}, :reaction_saved,
          room_id: message.room_id,
          message: message
        )

      {:error, reason} ->
        put_action(server, :send_failed, error: Chat.error_to_string(reason))
    end
  end

  def command(:run_search, params, server) do
    put_action(server, :search_loaded, results: Chat.search(params.query, params.user_id))
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
    <main class="h-screen min-h-[680px] bg-[var(--campfire-bg)] text-[var(--campfire-ink)]">
      <div class="grid h-full grid-cols-[minmax(0,1fr)] overflow-hidden md:grid-cols-[72px_292px_minmax(0,1fr)] xl:grid-cols-[72px_292px_minmax(0,1fr)_360px]">
        <aside class="hidden flex-col items-center gap-3 border-r border-white/8 bg-[var(--campfire-rail)] px-3 py-4 text-stone-200 md:flex">
          <button
            aria-label="Open workspace home"
            class="grid size-11 place-items-center rounded-lg bg-[var(--campfire-accent)] text-base font-black text-stone-950 shadow-sm transition hover:bg-[var(--campfire-accent-strong)] hover:text-stone-100"
            type="button"
            title="Workspace home"
            $click="rail_workspace"
          >
            JC
          </button>
          <button
            aria-label="Open channels"
            class="grid size-10 place-items-center rounded-md transition {if @rail_target == "channels" do "bg-white/18 text-white" else "bg-white/8 text-stone-200 hover:bg-white/12" end}"
            type="button"
            title="Channels"
            $click="rail_channels"
          >
            <span class="hero-chat-bubble-left-right size-5"></span>
          </button>
          <button
            aria-label="Open direct messages"
            class="grid size-10 place-items-center rounded-md transition {if @rail_target == "direct_messages" do "bg-white/18 text-white" else "bg-white/8 text-stone-200 hover:bg-white/12" end}"
            type="button"
            title="Direct messages"
            $click="rail_direct_messages"
          >
            <span class="hero-at-symbol size-5"></span>
          </button>
          <button
            aria-label="Focus search"
            class="grid size-10 place-items-center rounded-md transition {if @rail_target == "search" do "bg-white/18 text-white" else "bg-white/8 text-stone-200 hover:bg-white/12" end}"
            type="button"
            title="Search"
            $click="rail_search"
          >
            <span class="hero-magnifying-glass size-5"></span>
          </button>
          <button
            aria-label="Open demo user switcher"
            class="mt-auto grid size-10 place-items-center rounded-md border text-xs font-semibold transition {if @rail_target == "users" do "border-[var(--campfire-accent)] bg-[var(--campfire-accent)] text-stone-950" else "border-white/10 bg-white/6 text-stone-300 hover:bg-white/10" end}"
            type="button"
            title="Demo user"
            $click="rail_users"
          >
            {@current_user.initials}
          </button>
        </aside>

        <aside class="hidden min-h-0 flex-col bg-[var(--campfire-sidebar)] text-stone-100 md:flex">
          <header class="border-b border-white/8 px-5 py-4">
            <div class="flex items-center justify-between gap-3">
              <div class="min-w-0">
                <p class="text-xs font-semibold text-stone-400">Workspace</p>
                <h1 class="mt-1 truncate text-lg font-bold text-stone-50" id="campfire-workspace-heading">{@workspace.name}</h1>
              </div>
              <span class="rounded-md bg-[var(--campfire-green)]/18 px-2 py-1 text-xs font-semibold text-emerald-200">live</span>
            </div>

            <div class="mt-4" id="campfire-demo-users" tabindex="-1">
              <p class="mb-2 text-xs font-semibold text-stone-400">Demo user</p>
              <div class="grid grid-cols-2 gap-1.5">
                {%for user <- @demo_users}
                  <button
                    class="rounded-md border px-2 py-1.5 text-left text-xs font-semibold transition {if user.id == @current_user.id do "border-[var(--campfire-accent)] bg-[var(--campfire-accent)] text-stone-950" else "border-white/10 bg-white/6 text-stone-300 hover:bg-white/10" end}"
                    type="button"
                    $click={:select_user, id: user.id}
                  >
                    {user.name}
                  </button>
                {/for}
              </div>
            </div>

            <div class="mt-4">
              <div class="relative">
                <span class="hero-magnifying-glass pointer-events-none absolute left-3 top-2.5 size-4 text-stone-500"></span>
                <input
                  class="h-9 w-full rounded-md border bg-stone-950/35 pl-9 pr-3 text-sm text-stone-100 outline-none placeholder:text-stone-500 {if @rail_target == "search" do "border-[var(--campfire-accent)] ring-2 ring-[var(--campfire-accent)]/30" else "border-white/10" end}"
                  id="campfire-search-input"
                  name="search"
                  placeholder="Search messages"
                  value={@search_query}
                  $change="search_changed"
                />
              </div>
              {%if @search_results != []}
                <div class="mt-2 max-h-44 space-y-1 overflow-y-auto rounded-md border border-white/10 bg-stone-950/50 p-1">
                  {%for result <- @search_results}
                    <button
                      class="w-full rounded-md px-2 py-1.5 text-left transition hover:bg-white/8"
                      type="button"
                      $click={:select_search_result, room_id: result.room_id, thread_id: result.thread_id}
                    >
                      <span class="block truncate text-xs font-bold text-stone-200">{result.room_label} · {result.author}</span>
                      <span class="block truncate text-xs text-stone-400">{result.body}</span>
                    </button>
                  {/for}
                </div>
              {/if}
            </div>
          </header>

          <div class="min-h-0 flex-1 overflow-y-auto px-3 py-4">
            <section id="campfire-channels-section" tabindex="-1">
              <div class="mb-2 flex items-center justify-between px-2 text-xs font-semibold text-stone-400">
                <span>Channels</span>
                <button class="grid size-7 place-items-center rounded-md text-stone-300 transition hover:bg-white/8" type="button" title="New channel" $click="toggle_room_form">
                  <span class="hero-plus size-4"></span>
                </button>
              </div>

              {%if @room_form_open}
                <form class="mb-3 space-y-2 rounded-md border border-white/10 bg-white/6 p-2" $submit="create_channel">
                  <input
                    class="h-9 w-full rounded-md border border-white/10 bg-stone-950/30 px-3 text-sm text-stone-100 outline-none placeholder:text-stone-500"
                    name="name"
                    placeholder="channel-name"
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
                    {%if @new_room_pending}Creating{%else}Create channel{/if}
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
                    <span class="ml-2 flex shrink-0 items-center gap-1">
                      {%if channel.mention_unread > 0}
                        <span class="rounded-full bg-amber-200 px-1.5 py-0.5 text-[11px] font-bold text-amber-950">@{channel.mention_unread}</span>
                      {/if}
                      {%if channel.unread > 0}
                        <span class="rounded-full bg-[var(--campfire-accent)] px-2 py-0.5 text-xs font-bold text-stone-950">{channel.unread}</span>
                      {/if}
                    </span>
                  </button>
                {/for}
              </div>
            </section>

            <section class="mt-6" id="campfire-direct-messages-section" tabindex="-1">
              <div class="mb-2 px-2 text-xs font-semibold text-stone-400">Direct messages</div>
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
                <span class="hidden rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] px-3 py-2 text-sm font-semibold text-[var(--campfire-muted)] sm:inline-flex">
                  As {@current_user.name}
                </span>
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
              <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] px-4 py-3 text-sm text-[var(--campfire-muted)]">
                Durable SQLite history through jido_messaging, live Hologram broadcasts, one developer-demo workspace.
              </div>

              {%for message <- @messages}
                <article class="group flex gap-3 rounded-md px-1 py-1 transition hover:bg-[var(--campfire-panel-muted)]">
                  <div class="grid size-10 shrink-0 place-items-center rounded-md {message.tone} text-sm font-black">
                    {message.avatar}
                  </div>
                  <div class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-baseline gap-2">
                      <h3 class="text-sm font-bold text-[var(--campfire-ink)]">{message.author}</h3>
                      <time class="text-xs text-[var(--campfire-muted)]">{message.time}</time>
                      {%if message.own}
                        <span class="rounded-full bg-[var(--campfire-accent)]/20 px-2 py-0.5 text-xs font-semibold text-[var(--campfire-accent-strong)]">{message.status}</span>
                      {/if}
                      {%if message.mentions_current_user}
                        <span class="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-800">@you</span>
                      {/if}
                    </div>
                    <p class="mt-1 max-w-[74ch] text-sm leading-6 text-stone-700">{message.body}</p>
                    <div class="mt-2 flex flex-wrap items-center gap-1.5">
                      {%for reaction <- message.reactions}
                        <button
                          class="rounded-full border px-2 py-0.5 text-xs font-semibold transition {if reaction.reacted do "border-[var(--campfire-accent)] bg-[var(--campfire-accent)] text-stone-950" else "border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] text-stone-600 hover:bg-stone-200" end}"
                          type="button"
                          $click={:toggle_reaction, message_id: message.id, emoji: reaction.emoji}
                        >
                          {reaction.emoji} {reaction.count}
                        </button>
                      {/for}
                      {%for emoji <- @reaction_options}
                        <button
                          class="rounded-full border border-[var(--campfire-line)] bg-transparent px-2 py-0.5 text-xs font-semibold text-stone-500 opacity-100 transition hover:bg-[var(--campfire-panel-muted)] focus:opacity-100 sm:opacity-0 sm:group-hover:opacity-100"
                          type="button"
                          $click={:toggle_reaction, message_id: message.id, emoji: emoji}
                        >
                          {emoji}
                        </button>
                      {/for}
                      <button
                        class="ml-1 inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-semibold text-[var(--campfire-muted)] transition hover:bg-[var(--campfire-panel-muted)]"
                        type="button"
                        $click={:open_thread, message_id: message.id}
                      >
                        <span class="hero-chat-bubble-left-ellipsis size-4"></span>
                        {%if message.reply_count > 0}{message.reply_count} replies{%else}Reply{/if}
                      </button>
                    </div>
                  </div>
                </article>
              {/for}
            </div>
          </div>

          <footer class="border-t border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-4 py-4 sm:px-6">
            <form class="mx-auto flex max-w-4xl items-end gap-3 rounded-md border border-[var(--campfire-line)] bg-stone-50 p-2 shadow-sm" $submit="send_message">
              <textarea
                class="min-h-11 flex-1 resize-none rounded-md bg-transparent px-3 py-2 text-sm leading-6 text-[var(--campfire-ink)] outline-none placeholder:text-stone-400"
                name="body"
                placeholder="Message {@active_room_prefix} {@active_room_name}. Try @maggie"
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

        {%if @thread_open && @thread_root}
          <div class="fixed inset-x-0 bottom-0 z-30 max-h-[82vh] overflow-hidden border-t border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] shadow-2xl xl:hidden" role="dialog" aria-label="Thread">
            <header class="border-b border-[var(--campfire-line)] px-4 py-3">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <h2 class="text-sm font-bold text-[var(--campfire-ink)]">Thread</h2>
                  <p class="mt-1 truncate text-sm text-[var(--campfire-muted)]">{@active_room_prefix} {@active_room_name}</p>
                </div>
                <button class="grid size-9 shrink-0 place-items-center rounded-md text-[var(--campfire-muted)] transition hover:bg-stone-200" type="button" title="Close thread" $click="close_thread">
                  <span class="hero-x-mark size-5"></span>
                </button>
              </div>
            </header>
            <div class="max-h-[52vh] overflow-y-auto px-4 py-4">
              <article class="flex gap-3 rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-3">
                <div class="grid size-9 shrink-0 place-items-center rounded-md {@thread_root.tone} text-xs font-black">{@thread_root.avatar}</div>
                <div class="min-w-0">
                  <div class="flex flex-wrap items-baseline gap-2">
                    <h3 class="text-sm font-bold text-[var(--campfire-ink)]">{@thread_root.author}</h3>
                    <time class="text-xs text-[var(--campfire-muted)]">{@thread_root.time}</time>
                  </div>
                  <p class="mt-1 text-sm leading-6 text-stone-700">{@thread_root.body}</p>
                </div>
              </article>

              <div class="mt-4 space-y-4">
                {%for reply <- @thread_messages}
                  <article class="flex gap-3">
                    <div class="grid size-8 shrink-0 place-items-center rounded-md {reply.tone} text-xs font-black">{reply.avatar}</div>
                    <div class="min-w-0">
                      <div class="flex flex-wrap items-baseline gap-2">
                        <h3 class="text-sm font-bold text-[var(--campfire-ink)]">{reply.author}</h3>
                        <time class="text-xs text-[var(--campfire-muted)]">{reply.time}</time>
                      </div>
                      <p class="mt-1 text-sm leading-6 text-stone-700">{reply.body}</p>
                    </div>
                  </article>
                {/for}
              </div>
            </div>
            <footer class="border-t border-[var(--campfire-line)] p-3">
              <form class="flex items-end gap-2 rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-2" $submit="send_reply">
                <textarea
                  class="min-h-10 flex-1 resize-none rounded-md bg-transparent px-2 py-2 text-sm text-[var(--campfire-ink)] outline-none placeholder:text-stone-400"
                  name="reply"
                  placeholder="Reply in thread"
                  rows="1"
                  value={@reply_draft}
                  $change="reply_draft_changed"
                />
                <button class="grid size-9 shrink-0 place-items-center rounded-md bg-[var(--campfire-ink)] text-stone-100 transition hover:bg-stone-800 disabled:opacity-60" type="submit" disabled={@reply_pending} title="Send reply">
                  <span class="hero-paper-airplane size-4"></span>
                </button>
              </form>
              {%if @reply_error}
                <p class="mt-2 text-sm font-semibold text-amber-700">{@reply_error}</p>
              {/if}
            </footer>
          </div>
        {/if}

        <aside class="hidden min-h-0 flex-col border-l border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] xl:flex">
          {%if @thread_open && @thread_root}
            <header class="border-b border-[var(--campfire-line)] px-5 py-4">
              <div class="flex items-center justify-between gap-3">
                <div>
                  <h2 class="text-sm font-bold text-[var(--campfire-ink)]">Thread</h2>
                  <p class="mt-1 text-sm text-[var(--campfire-muted)]">{@active_room_prefix} {@active_room_name}</p>
                </div>
                <button class="grid size-8 place-items-center rounded-md text-[var(--campfire-muted)] transition hover:bg-stone-200" type="button" title="Close thread" $click="close_thread">
                  <span class="hero-x-mark size-5"></span>
                </button>
              </div>
            </header>
            <div class="min-h-0 flex-1 overflow-y-auto p-5">
              <article class="flex gap-3 rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-3">
                <div class="grid size-9 shrink-0 place-items-center rounded-md {@thread_root.tone} text-xs font-black">{@thread_root.avatar}</div>
                <div class="min-w-0">
                  <div class="flex items-baseline gap-2">
                    <h3 class="text-sm font-bold text-[var(--campfire-ink)]">{@thread_root.author}</h3>
                    <time class="text-xs text-[var(--campfire-muted)]">{@thread_root.time}</time>
                  </div>
                  <p class="mt-1 text-sm leading-6 text-stone-700">{@thread_root.body}</p>
                </div>
              </article>

              <div class="mt-4 space-y-4">
                {%for reply <- @thread_messages}
                  <article class="flex gap-3">
                    <div class="grid size-8 shrink-0 place-items-center rounded-md {reply.tone} text-xs font-black">{reply.avatar}</div>
                    <div class="min-w-0">
                      <div class="flex items-baseline gap-2">
                        <h3 class="text-sm font-bold text-[var(--campfire-ink)]">{reply.author}</h3>
                        <time class="text-xs text-[var(--campfire-muted)]">{reply.time}</time>
                      </div>
                      <p class="mt-1 text-sm leading-6 text-stone-700">{reply.body}</p>
                    </div>
                  </article>
                {/for}
              </div>
            </div>
            <footer class="border-t border-[var(--campfire-line)] p-4">
              <form class="flex items-end gap-2 rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-2" $submit="send_reply">
                <textarea
                  class="min-h-10 flex-1 resize-none rounded-md bg-transparent px-2 py-2 text-sm text-[var(--campfire-ink)] outline-none placeholder:text-stone-400"
                  name="reply"
                  placeholder="Reply in thread"
                  rows="1"
                  value={@reply_draft}
                  $change="reply_draft_changed"
                />
                <button class="grid size-9 place-items-center rounded-md bg-[var(--campfire-ink)] text-stone-100 transition hover:bg-stone-800 disabled:opacity-60" type="submit" disabled={@reply_pending} title="Send reply">
                  <span class="hero-paper-airplane size-4"></span>
                </button>
              </form>
              {%if @reply_error}
                <p class="mt-2 text-sm font-semibold text-amber-700">{@reply_error}</p>
              {/if}
            </footer>
          {%else}
            <header class="border-b border-[var(--campfire-line)] px-5 py-4">
              <h2 class="text-sm font-bold text-[var(--campfire-ink)]">Developer inspector</h2>
              <p class="mt-1 text-sm text-[var(--campfire-muted)]">{@active_room_prefix} {@active_room_name}</p>
            </header>
            <div class="space-y-5 overflow-y-auto p-5">
              <section>
                <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Conversation state</h3>
                <div class="space-y-2">
                  {%for metric <- @developer_room_metrics}
                    <div class="flex items-center justify-between rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-3 py-2 text-sm">
                      <span>{metric.label}</span>
                      <span class="font-semibold text-stone-700">{metric.value}</span>
                    </div>
                  {/for}
                </div>
              </section>

              <section>
                <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Last event</h3>
                <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-3 text-sm">
                  <div class="flex items-center justify-between gap-3">
                    <span class="font-bold text-stone-800">{@last_event.title}</span>
                    <span class="rounded-md bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-800">{@last_event.layer}</span>
                  </div>
                  <p class="mt-2 leading-6 text-stone-700">{@last_event.detail}</p>
                </div>
              </section>

              <section>
                <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Jido Chat contract</h3>
                <div class="space-y-2">
                  {%for item <- @developer_contract}
                    <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-3 py-2 text-sm">
                      <div class="flex items-center justify-between gap-3">
                        <span>{item.label}</span>
                        <span class="font-semibold text-stone-700">{item.value}</span>
                      </div>
                      <p class="mt-1 text-xs leading-5 text-[var(--campfire-muted)]">{item.detail}</p>
                    </div>
                  {/for}
                </div>
              </section>

              <section>
                <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Stack path</h3>
                <div class="space-y-2">
                  {%for layer <- @developer_stack}
                    <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] p-3">
                      <div class="flex items-center justify-between gap-3">
                        <h4 class="text-sm font-bold text-[var(--campfire-ink)]">{layer.name}</h4>
                        <span class="rounded-md bg-[var(--campfire-panel-muted)] px-2 py-0.5 text-xs font-semibold text-[var(--campfire-muted)]">{layer.badge}</span>
                      </div>
                      <p class="mt-2 text-xs leading-5 text-stone-700">{layer.role}</p>
                    </div>
                  {/for}
                </div>
              </section>

              <section>
                <h3 class="mb-2 text-xs font-semibold text-[var(--campfire-muted)]">Demo scope</h3>
                <div class="space-y-2">
                  {%for capability <- @developer_capabilities}
                    <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel)] px-3 py-2 text-sm">
                      <div class="flex items-center justify-between gap-3">
                        <span class="font-semibold text-stone-800">{capability.feature}</span>
                        <span class="text-xs font-semibold {if capability.status == "implemented" do "text-emerald-700" else "text-stone-500" end}">{capability.status}</span>
                      </div>
                      <p class="mt-1 text-xs leading-5 text-[var(--campfire-muted)]">{capability.detail}</p>
                    </div>
                  {/for}
                </div>
              </section>
            </div>
          {/if}
        </aside>
      </div>
    </main>
    """
  end

  defp apply_snapshot(component, snapshot) do
    component
    |> put_state(:workspace, snapshot.workspace)
    |> put_state(:current_user, snapshot.current_user)
    |> put_state(:demo_users, snapshot.demo_users)
    |> put_state(:reaction_options, snapshot.reaction_options)
    |> put_state(:rooms, snapshot.rooms)
    |> put_state(:channels, snapshot.channels)
    |> put_state(:direct_messages, snapshot.direct_messages)
    |> put_state(:messages_by_room, snapshot.messages_by_room)
    |> put_state(:threads_by_room, snapshot.threads_by_room)
    |> put_state(:active_room, snapshot.active_room)
    |> put_state(:active_room_id, snapshot.active_room_id)
    |> put_state(:active_room_name, snapshot.active_room_name)
    |> put_state(:active_room_kind, snapshot.active_room_kind)
    |> put_state(:active_room_prefix, snapshot.active_room_prefix)
    |> put_state(:active_topic, snapshot.active_topic)
    |> put_state(:member_count_label, snapshot.member_count_label)
    |> put_state(:messages, snapshot.messages)
    |> put_state(:message_count, Enum.count(snapshot.messages))
    |> put_state(:developer_stack, snapshot.developer_showcase.stack)
    |> put_state(:developer_capabilities, snapshot.developer_showcase.capabilities)
    |> put_state(:developer_contract_by_room, snapshot.developer_showcase.contracts_by_room)
    |> put_state(:developer_contract, snapshot.developer_showcase.chat_contract)
    |> put_state(:developer_room_metrics, snapshot.developer_showcase.room_metrics)
    |> put_state(:last_event, snapshot.developer_showcase.last_event)
  end

  defp select_room(component, room_id) do
    room = Enum.find(component.state.rooms, &(&1.id == room_id)) || component.state.active_room
    messages = Map.get(component.state.messages_by_room, room.id, [])
    rooms = clear_unread(component.state.rooms, room.id)

    component
    |> put_rooms(rooms)
    |> put_state(:rail_target, rail_target_for_room(room))
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
    |> put_state(:thread_open, false)
    |> put_state(:thread_root, nil)
    |> put_state(:thread_messages, [])
    |> put_active_developer_context(
      developer_event("Room selected", "Hologram action", "#{room.prefix}#{room.name}")
    )
  end

  defp select_first_room(component, []), do: component

  defp select_first_room(component, [room | _rooms]) do
    select_room(component, room.id)
  end

  defp put_active_developer_context(component, event) do
    room = component.state.active_room
    thread_count = component.state.threads_by_room |> Map.get(room.id, %{}) |> map_size()

    contract =
      Map.get(
        component.state.developer_contract_by_room,
        room.id,
        fallback_developer_contract(room)
      )

    component
    |> put_state(
      :developer_room_metrics,
      developer_room_metrics(room, component.state.message_count, thread_count)
    )
    |> put_state(:developer_contract, contract)
    |> put_state(:last_event, event)
  end

  defp developer_room_metrics(room, message_count, thread_count) do
    [
      %{label: "Room", value: "#{room.prefix}#{room.name}"},
      %{label: "Type", value: room.kind},
      %{label: "Messages", value: Integer.to_string(message_count)},
      %{label: "Threads", value: Integer.to_string(thread_count)},
      %{label: "Durability", value: "SQLite"}
    ]
  end

  defp fallback_developer_contract(room) do
    target_kind = if room.kind == "dm", do: "dm", else: "room"

    [
      %{
        label: "Target",
        value: "#{target_kind} #{room.id}",
        detail: "Jido.Chat.MessagingTarget"
      },
      %{label: "Payload", value: "text", detail: "Jido.Chat.PostPayload"},
      %{
        label: "Write path",
        value: "save_message",
        detail: "Jido.Campfire.Messaging to jido_messaging"
      }
    ]
  end

  defp developer_event(title, layer, detail) do
    %{
      title: title,
      layer: layer,
      detail: detail
    }
  end

  defp room_label(component, room_id) do
    case Enum.find(component.state.rooms, &(&1.id == room_id)) do
      nil -> room_id
      room -> "#{room.prefix}#{room.name}"
    end
  end

  defp rail_target_for_room(%{kind: "dm"}), do: "direct_messages"
  defp rail_target_for_room(_room), do: "channels"

  defp focus_rail_target(:workspace) do
    JS.exec("""
    document.getElementById("campfire-workspace-heading")?.scrollIntoView({ block: "nearest" });
    """)
  end

  defp focus_rail_target(:channels) do
    JS.exec("""
    const target = document.getElementById("campfire-channels-section");
    target?.scrollIntoView({ block: "nearest" });
    target?.focus({ preventScroll: true });
    """)
  end

  defp focus_rail_target(:direct_messages) do
    JS.exec("""
    const target = document.getElementById("campfire-direct-messages-section");
    target?.scrollIntoView({ block: "nearest" });
    target?.focus({ preventScroll: true });
    """)
  end

  defp focus_rail_target(:search) do
    JS.exec("""
    const target = document.getElementById("campfire-search-input");
    target?.scrollIntoView({ block: "nearest" });
    target?.focus();
    """)
  end

  defp focus_rail_target(:users) do
    JS.exec("""
    const target = document.getElementById("campfire-demo-users");
    target?.scrollIntoView({ block: "nearest" });
    target?.focus({ preventScroll: true });
    """)
  end

  defp put_timeline_message(component, room_id, message) do
    messages_for_room = Map.get(component.state.messages_by_room, room_id, [])
    messages_for_room = upsert_message(messages_for_room, message)
    messages_by_room = Map.put(component.state.messages_by_room, room_id, messages_for_room)

    component
    |> put_state(:messages_by_room, messages_by_room)
    |> put_state(:messages, active_messages(component, room_id, messages_for_room))
    |> put_state(:message_count, active_message_count(component, room_id, messages_for_room))
  end

  defp put_thread_reply(component, room_id, message) do
    room_threads = Map.get(component.state.threads_by_room, room_id, %{})
    thread_messages = room_threads |> Map.get(message.thread_id, []) |> upsert_message(message)
    room_threads = Map.put(room_threads, message.thread_id, thread_messages)
    threads_by_room = Map.put(component.state.threads_by_room, room_id, room_threads)

    messages_by_room =
      update_root_reply_count(
        component.state.messages_by_room,
        room_id,
        message.thread_id,
        Enum.count(thread_messages)
      )

    component =
      component
      |> put_state(:threads_by_room, threads_by_room)
      |> put_state(:messages_by_room, messages_by_room)
      |> put_state(
        :messages,
        Map.get(messages_by_room, component.state.active_room_id, component.state.messages)
      )

    if component.state.thread_open && component.state.thread_root &&
         component.state.thread_root.id == message.thread_id do
      put_state(component, :thread_messages, thread_messages)
    else
      component
    end
  end

  defp update_message_everywhere(component, message) do
    if Map.get(message, :is_reply, false) do
      put_thread_reply(component, message.room_id, message)
    else
      put_timeline_message(component, message.room_id, message)
    end
  end

  defp upsert_message(messages, new_message) do
    if Enum.any?(messages, &(&1.id == new_message.id)) do
      Enum.map(messages, fn message ->
        if message.id == new_message.id,
          do: preserve_reply_count(message, new_message),
          else: message
      end)
    else
      messages ++ [new_message]
    end
  end

  defp preserve_reply_count(old_message, new_message) do
    Map.put(
      new_message,
      :reply_count,
      Map.get(new_message, :reply_count, old_message.reply_count)
    )
  end

  defp update_root_reply_count(messages_by_room, room_id, root_id, reply_count) do
    messages =
      messages_by_room
      |> Map.get(room_id, [])
      |> Enum.map(fn message ->
        if message.id == root_id, do: Map.put(message, :reply_count, reply_count), else: message
      end)

    Map.put(messages_by_room, room_id, messages)
  end

  defp get_thread_messages(_component, nil), do: []

  defp get_thread_messages(component, root_id) do
    component.state.threads_by_room
    |> Map.get(component.state.active_room_id, %{})
    |> Map.get(root_id, [])
  end

  defp personalize_message(message, user_id) do
    reactions =
      Enum.map(Map.get(message, :reactions, []), fn reaction ->
        user_ids = Map.get(reaction, :user_ids, [])

        reaction
        |> Map.put(:user_ids, user_ids)
        |> Map.put(:reacted, user_id in user_ids)
      end)

    message
    |> Map.put(:own, message.sender_id == user_id)
    |> Map.put(:mentions_current_user, user_id in Map.get(message, :mentioned_user_ids, []))
    |> Map.put(:reactions, reactions)
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

  defp touch_room(rooms, room_id, active_room_id, own_message, mentions_current_user) do
    Enum.map(rooms, fn room ->
      cond do
        room.id == room_id and room.id == active_room_id ->
          room |> Map.put(:unread, 0) |> Map.put(:mention_unread, 0)

        room.id == room_id and own_message ->
          room

        room.id == room_id ->
          room
          |> Map.put(:unread, room.unread + 1)
          |> Map.put(
            :mention_unread,
            room.mention_unread + if(mentions_current_user, do: 1, else: 0)
          )

        true ->
          room
      end
    end)
  end

  defp clear_unread(rooms, room_id) do
    Enum.map(rooms, fn room ->
      if room.id == room_id do
        room |> Map.put(:unread, 0) |> Map.put(:mention_unread, 0)
      else
        room
      end
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
