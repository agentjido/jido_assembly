defmodule Jido.Assembly.Components.Assembly.ThreadPanel do
  use Hologram.Component

  prop :active_room_name, :string
  prop :active_room_prefix, :string
  prop :reply_draft, :string
  prop :reply_error, :any
  prop :reply_pending, :boolean
  prop :thread_messages, :list
  prop :thread_open, :boolean
  prop :thread_root, :any

  def template do
    ~HOLO"""
    {%if @thread_open && @thread_root}
      <div class="fixed inset-x-0 bottom-0 z-30 max-h-[82vh] overflow-hidden border-t border-[var(--assembly-line)] bg-[var(--assembly-panel-muted)] shadow-2xl xl:hidden" role="dialog" aria-label="Thread">
        <header class="border-b border-[var(--assembly-line)] px-4 py-3">
          <div class="flex items-center justify-between gap-3">
            <div class="min-w-0">
              <h2 class="text-sm font-bold text-[var(--assembly-ink)]">Thread</h2>
              <p class="mt-1 truncate text-sm text-[var(--assembly-muted)]">{@active_room_prefix} {@active_room_name}</p>
            </div>
            <button class="grid size-9 shrink-0 place-items-center rounded-md text-[var(--assembly-muted)] transition hover:bg-stone-200" type="button" title="Close thread" $click="close_thread">
              <span class="hero-x-mark size-5"></span>
            </button>
          </div>
        </header>
        <div class="max-h-[52vh] overflow-y-auto px-4 py-4">
          <article class="flex gap-3 rounded-md border border-[var(--assembly-line)] bg-[var(--assembly-panel)] p-3">
            <div class="grid size-9 shrink-0 place-items-center rounded-md {@thread_root.tone} text-xs font-black">{@thread_root.avatar}</div>
            <div class="min-w-0">
              <div class="flex flex-wrap items-baseline gap-2">
                <h3 class="text-sm font-bold text-[var(--assembly-ink)]">{@thread_root.author}</h3>
                <time class="text-xs text-[var(--assembly-muted)]">{@thread_root.time}</time>
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
                    <h3 class="text-sm font-bold text-[var(--assembly-ink)]">{reply.author}</h3>
                    <time class="text-xs text-[var(--assembly-muted)]">{reply.time}</time>
                  </div>
                  <p class="mt-1 text-sm leading-6 text-stone-700">{reply.body}</p>
                </div>
              </article>
            {/for}
          </div>
        </div>
        <footer class="border-t border-[var(--assembly-line)] p-3">
          <form data-assembly-composer="reply" class="flex items-end gap-2 rounded-lg border border-[var(--assembly-line)] bg-[var(--assembly-panel)] p-2 transition focus-within:border-[var(--assembly-accent)] focus-within:ring-2 focus-within:ring-[var(--assembly-accent)]/20" $submit="send_reply">
            <input
              class="h-10 min-w-0 flex-1 rounded-md bg-transparent px-2 py-2 text-sm text-[var(--assembly-ink)] outline-none placeholder:text-stone-400"
              aria-label="Thread reply"
              autocomplete="off"
              name="reply"
              placeholder="Reply in thread"
              type="text"
              value={@reply_draft}
              $input="reply_draft_changed"
            />
            <button class="grid size-9 shrink-0 place-items-center rounded-md bg-[var(--assembly-ink)] text-stone-100 transition hover:bg-stone-800 disabled:opacity-60" type="submit" disabled={@reply_pending} title="Send reply">
              <span class="hero-paper-airplane size-4"></span>
            </button>
          </form>
          {%if @reply_error}
            <p class="mt-2 text-sm font-semibold text-amber-700">{@reply_error}</p>
          {/if}
        </footer>
      </div>

      <aside class="hidden min-h-0 flex-col border-l border-[var(--assembly-line)] bg-[var(--assembly-panel-muted)] xl:flex">
        <header class="border-b border-[var(--assembly-line)] px-5 py-4">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h2 class="text-sm font-bold text-[var(--assembly-ink)]">Thread</h2>
              <p class="mt-1 text-sm text-[var(--assembly-muted)]">{@active_room_prefix} {@active_room_name}</p>
            </div>
            <button class="grid size-8 place-items-center rounded-md text-[var(--assembly-muted)] transition hover:bg-stone-200" type="button" title="Close thread" $click="close_thread">
              <span class="hero-x-mark size-5"></span>
            </button>
          </div>
        </header>
        <div class="min-h-0 flex-1 overflow-y-auto p-5">
          <article class="flex gap-3 rounded-md border border-[var(--assembly-line)] bg-[var(--assembly-panel)] p-3">
            <div class="grid size-9 shrink-0 place-items-center rounded-md {@thread_root.tone} text-xs font-black">{@thread_root.avatar}</div>
            <div class="min-w-0">
              <div class="flex items-baseline gap-2">
                <h3 class="text-sm font-bold text-[var(--assembly-ink)]">{@thread_root.author}</h3>
                <time class="text-xs text-[var(--assembly-muted)]">{@thread_root.time}</time>
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
                    <h3 class="text-sm font-bold text-[var(--assembly-ink)]">{reply.author}</h3>
                    <time class="text-xs text-[var(--assembly-muted)]">{reply.time}</time>
                  </div>
                  <p class="mt-1 text-sm leading-6 text-stone-700">{reply.body}</p>
                </div>
              </article>
            {/for}
          </div>
        </div>
        <footer class="border-t border-[var(--assembly-line)] p-4">
          <form data-assembly-composer="reply" class="flex items-end gap-2 rounded-lg border border-[var(--assembly-line)] bg-[var(--assembly-panel)] p-2 transition focus-within:border-[var(--assembly-accent)] focus-within:ring-2 focus-within:ring-[var(--assembly-accent)]/20" $submit="send_reply">
            <input
              class="h-10 min-w-0 flex-1 rounded-md bg-transparent px-2 py-2 text-sm text-[var(--assembly-ink)] outline-none placeholder:text-stone-400"
              aria-label="Thread reply"
              autocomplete="off"
              name="reply"
              placeholder="Reply in thread"
              type="text"
              value={@reply_draft}
              $input="reply_draft_changed"
            />
            <button class="grid size-9 place-items-center rounded-md bg-[var(--assembly-ink)] text-stone-100 transition hover:bg-stone-800 disabled:opacity-60" type="submit" disabled={@reply_pending} title="Send reply">
              <span class="hero-paper-airplane size-4"></span>
            </button>
          </form>
          {%if @reply_error}
            <p class="mt-2 text-sm font-semibold text-amber-700">{@reply_error}</p>
          {/if}
        </footer>
      </aside>
    {/if}
    """
  end
end
