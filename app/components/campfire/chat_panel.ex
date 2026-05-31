defmodule Jido.Campfire.Components.Campfire.ChatPanel do
  use Hologram.Component

  prop :active_room_id, :string
  prop :active_room_name, :string
  prop :active_room_prefix, :string
  prop :active_topic, :string
  prop :agent_demo, :map
  prop :agent_error, :any
  prop :agent_inter_agent_enabled, :boolean
  prop :agent_prompt_draft, :string
  prop :agent_round_pending, :boolean
  prop :agent_safety_enabled, :boolean
  prop :current_user, :map
  prop :draft, :string
  prop :error, :any
  prop :member_count_label, :string
  prop :messages, :list
  prop :rooms, :list
  prop :send_pending, :boolean
  prop :workspace, :map

  def template do
    ~HOLO"""
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

        <div class="mt-3 grid gap-2 rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] px-3 py-2 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
          <div class="flex min-w-0 flex-wrap items-center gap-2">
            <span class="inline-flex items-center gap-1.5 text-xs font-bold uppercase tracking-wide text-[var(--campfire-muted)]">
              <span class="hero-sparkles size-4"></span>
              AI agents
            </span>
            {%for agent <- @agent_demo.agents}
              <span class="inline-flex items-center gap-1.5 rounded-full border border-[var(--campfire-line)] bg-white px-2 py-1 text-xs font-semibold text-stone-700" title={agent.title}>
                <span class="grid size-5 place-items-center rounded {agent.tone} text-[10px] font-black">{agent.initials}</span>
                {agent.name}
              </span>
            {/for}
            <span class="inline-flex h-7 items-center rounded-full border border-[var(--campfire-line)] bg-white px-2 text-xs font-semibold text-[var(--campfire-muted)]">
              {@agent_demo.safety.max_rounds_per_prompt} rounds/question
            </span>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <label class="inline-flex h-8 items-center gap-1.5 rounded-md border border-[var(--campfire-line)] bg-white px-2.5 text-xs font-semibold text-stone-700">
              <input
                class="size-3.5 accent-[var(--campfire-accent)]"
                type="checkbox"
                checked={@agent_safety_enabled}
                $change="agent_safety_changed"
              />
              Safety cap
            </label>

            <label class="inline-flex h-8 items-center gap-1.5 rounded-md border border-[var(--campfire-line)] bg-white px-2.5 text-xs font-semibold text-stone-700">
              <input
                class="size-3.5 accent-[var(--campfire-accent)]"
                type="checkbox"
                checked={@agent_inter_agent_enabled}
                $change="agent_inter_agent_changed"
              />
              Agent chat
            </label>

            <button
              class="inline-flex h-8 items-center gap-2 rounded-md bg-stone-900 px-3 text-xs font-bold text-white transition hover:bg-stone-700 disabled:opacity-50"
              type="button"
              disabled={@agent_round_pending || @agent_demo.missing_api_key}
              title="Continue latest human prompt"
              $click="run_agent_round"
            >
              <span class="hero-bolt size-4"></span>
              {%if @agent_round_pending}Running{%else}Continue{/if}
            </button>
          </div>

          <form class="flex min-w-0 gap-2 lg:col-span-2" $submit="prompt_agent_round">
            <input
              class="h-9 min-w-0 flex-1 rounded-md border border-[var(--campfire-line)] bg-white px-3 text-sm text-[var(--campfire-ink)] outline-none placeholder:text-stone-400 focus:border-[var(--campfire-accent)] focus:ring-2 focus:ring-[var(--campfire-accent)]/20"
              aria-label="Ask AI agents"
              autocomplete="off"
              name="agent_prompt"
              placeholder="Ask Alice, Bob, and Charlie"
              type="text"
              value={@agent_prompt_draft}
              $input="agent_prompt_changed"
            />
            <button
              class="inline-flex h-9 items-center gap-2 rounded-md bg-[var(--campfire-accent)] px-3 text-xs font-bold text-stone-950 transition hover:bg-[var(--campfire-accent-strong)] hover:text-stone-100 disabled:opacity-50"
              type="submit"
              disabled={@agent_round_pending || @agent_demo.missing_api_key}
              title="Ask agents"
            >
              <span class="hero-paper-airplane size-4"></span>
              Ask
            </button>
          </form>
        </div>

        {%if @agent_error}
          <p class="mt-2 text-sm font-semibold text-amber-700">{@agent_error}</p>
        {/if}
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto px-4 py-5 sm:px-6">
        <div class="mx-auto max-w-4xl space-y-5">
          <div class="rounded-md border border-[var(--campfire-line)] bg-[var(--campfire-panel-muted)] px-4 py-3 text-sm text-[var(--campfire-muted)]">
            Durable SQLite history through jido_messaging, live Hologram broadcasts, one developer-demo workspace.
          </div>

          {%for message <- @messages}
            <article class="group flex gap-3 rounded-lg px-3 py-2.5 transition hover:bg-[var(--campfire-panel-muted)]">
              <div class="grid size-9 shrink-0 place-items-center rounded-lg {message.tone} text-xs font-black shadow-sm">
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
                      class="inline-flex h-7 items-center gap-1.5 rounded-full border px-2.5 text-xs font-semibold shadow-sm transition {if reaction.reacted do "border-[var(--campfire-accent)] bg-[var(--campfire-accent)]/25 text-stone-950" else "border-[var(--campfire-line)] bg-[var(--campfire-panel)] text-stone-600 hover:border-stone-300 hover:bg-stone-100" end}"
                      type="button"
                      title={reaction.label}
                      $click={:toggle_reaction, message_id: message.id, emoji: reaction.emoji}
                    >
                      <span class="text-sm leading-none">{reaction.glyph}</span>
                      <span>{reaction.count}</span>
                    </button>
                  {/for}
                  {%for option <- message.available_reactions}
                    <button
                      class="inline-flex h-7 items-center gap-1.5 rounded-full border border-[var(--campfire-line)] bg-[var(--campfire-panel)]/70 px-2 text-xs font-semibold text-stone-600 transition hover:border-stone-300 hover:bg-stone-100 hover:text-stone-900"
                      type="button"
                      title={option.label}
                      aria-label={option.label}
                      $click={:toggle_reaction, message_id: message.id, emoji: option.key}
                    >
                      <span class="text-sm leading-none">{option.glyph}</span>
                      <span class="hidden sm:inline">{option.label}</span>
                    </button>
                  {/for}
                  <button
                    class="ml-1 inline-flex h-7 items-center gap-1.5 rounded-full border border-transparent px-2.5 text-xs font-semibold text-[var(--campfire-muted)] transition hover:border-[var(--campfire-line)] hover:bg-[var(--campfire-panel)] hover:text-stone-800"
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
        <form data-campfire-composer="message" class="mx-auto flex max-w-4xl items-end gap-3 rounded-lg border border-[var(--campfire-line)] bg-white p-2 shadow-sm transition focus-within:border-[var(--campfire-accent)] focus-within:ring-2 focus-within:ring-[var(--campfire-accent)]/20" $submit="send_message">
          <input
            class="h-11 min-w-0 flex-1 rounded-md bg-transparent px-3 py-2 text-sm leading-6 text-[var(--campfire-ink)] outline-none placeholder:text-stone-400"
            aria-label="Message body"
            autocomplete="off"
            name="body"
            placeholder="Message {@active_room_prefix} {@active_room_name}. Try @maggie"
            type="text"
            value={@draft}
            $input="draft_changed"
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
    """
  end
end
