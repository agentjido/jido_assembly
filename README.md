# Jido Campfire

`jido_campfire` is a Hologram/Phoenix spike for a Slack-like Jido workspace backed by `jido_messaging`.
The package module prefix is `Jido.Campfire`.

## Run

```sh
mix setup
mix holo
```

Then open [`localhost:4000`](http://localhost:4000).

Use `mix holo` instead of `mix phx.server` when working on Hologram pages. In
dev and test, Hologram only starts when `HOLOGRAM_START=1`, which `mix holo`
sets for you.

## Spike Scope

- Hologram route at `/`
- Responsive Slack-like shell with workspace rail, channels, timeline, composer,
  and room context panel
- One seeded workspace with multiple group chats and DMs
- `Jido.Campfire.Messaging` using `Jido.Messaging.Persistence.ETS`
- Messages, participants, DMs, and group rooms persisted through `jido_messaging`
- Hologram realtime workspace broadcasts for sends and group chat creation
- Client-side room switching, unread counters, and responsive mobile room switcher
- Phoenix fallback health page at `/health`

## Testing Story

Campfire now has Hologram-focused ExUnit coverage in
`test/jido_campfire/pages/campfire_page_test.exs`. These tests exercise the
parts of Hologram that are most testable today: page `init/3`, template
evaluation, client `action/3` state transitions, server `command/3` handling,
and queued Hologram broadcasts.

Compared with Phoenix LiveView testing, this is lower-level. Hologram actions
and commands are easy to unit test because they return `%Hologram.Component{}`
and `%Hologram.Server{}` structs, but Hologram does not currently provide a
LiveViewTest-style DOM/event DSL for full in-process interaction tests.

Compared with Playwright, these tests are faster and more deterministic, but
they do not prove browser behavior, CSS/layout, JavaScript interop, SSE
delivery, or cross-tab realtime updates. Keep Playwright for the end-to-end
checks that matter to a chat product: two browser sessions, realtime sends,
room creation propagation, mobile layout, focus/keyboard behavior, and visual
overflow.

`Hologram.Test.setup/0` exists for browser/feature tests, but in this app it
needs the Campfire Hologram patch/prune path because `jido_messaging` pulls in
server-only transitive BEAM modules that Hologram `0.9.1` tries to reflect over.
That makes the current feature-test story workable, but not as mature as
Phoenix LiveView's built-in test ergonomics.

## Hologram Note

`jido_messaging` currently pulls in a transitive Erlang dependency with BEAM debug info that Hologram `0.9.1` cannot reflect over. `mix setup` applies a narrow local patch to `deps/hologram/lib/hologram/reflection.ex` so unsupported BEAM debug info is skipped instead of crashing the Hologram compiler.

## Next Slices

- Swap ETS for durable persistence
- Add real user/workspace identity
- Bind group rooms to Slack, Discord, or Mattermost adapters
- Attach Room Assistant to room message signals

See `ROADMAP.md` for a fuller product and platform roadmap against Slack-like
alternatives.
