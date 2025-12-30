AGENTS.md

AI Coding Agent Instructions for the Neovim Poker Plugin

This document defines the rules, expectations, and workflows that the Codex coding agent must follow when working inside this repository. The goal is deterministic, test-driven development with zero regressions, full test coverage, and safe, incremental improvements.

The plugin is a poker game for Neovim, written in Lua, using busted as the test framework.

1. Repository Context
Directory Layout
.
├─ AGENTS.md
├─ README.md
├─ after/
│  └─ plugin/poker.lua
├─ plugin/mappings.lua
├─ lua/
│  └─ poker/
│     ├─ init.lua
│     ├─ utils.lua
│     ├─ cards.lua
│     ├─ hand_evaluator.lua
│     ├─ match.lua
│     ├─ match/
│     │  ├─ logging.lua
│     │  └─ persistence.lua
│     ├─ window.lua
│     ├─ window/
│     │  ├─ layout.lua
│     │  ├─ event_feed.lua
│     │  └─ render.lua
│     ├─ commands.lua
│     ├─ stats.lua
│     ├─ ai.lua
│     ├─ batch_cli.lua
│     ├─ simulator.lua
│     ├─ sim_cli.lua
│     ├─ auto_tune.lua
│     ├─ run_tuner.lua
│     ├─ parse_log.lua
│     ├─ json.lua
│     ├─ fs.lua
│     ├─ frequency_error.lua
│     ├─ frequency_tracker.lua
│     ├─ target_frequencies.lua
│     ├─ tuning_params.lua
│     ├─ ai/
│     │  ├─ strategy.lua
│     │  ├─ opponent_model.lua
│     │  ├─ equity.lua
│     │  ├─ preflop_ranges.lua
│     │  └─ range_buckets.lua
│     └─ export/
│        ├─ acpc.lua
│        └─ pokerstars.lua
├─ tests/
│  ├─ helpers/mock_vim.lua
│  ├─ ai_spec.lua
│  ├─ ai/
│  │  ├─ ai_decision_spec.lua
│  │  ├─ buckets_spec.lua
│  │  ├─ cbet_spec.lua
│  │  ├─ opponent_model_spec.lua
│  │  ├─ probabilistic_spec.lua
│  │  ├─ semi_bluff_spec.lua
│  │  └─ strategy_spec.lua
│  ├─ export/
│  │  ├─ acpc_spec.lua
│  │  ├─ end_to_end_spec.lua
│  │  ├─ pokerstars_spec.lua
│  │  └─ simulator_spec.lua
│  ├─ cards_spec.lua
│  ├─ batch_cli_spec.lua
│  ├─ commands_spec.lua
│  ├─ fs_spec.lua
│  ├─ hand_evaluator_spec.lua
│  ├─ json_spec.lua
│  ├─ match_spec.lua
│  ├─ stats_spec.lua
│  ├─ utils_spec.lua
│  ├─ window_spec.lua
│  └─ test_regression.lua
├─ data/ (simulation and tuning artifacts)
├─ scripts/run_simulator.sh
├─ run_batch.sh
└─ analysis.json, observed_freq.json, tuning_history (supporting data files)

Technologies Used

Lua (Neovim plugin ecosystem)

busted (describe, it, before_each, assert.is_true, etc.)

mock_vim.lua for injecting Neovim internals

plenary (popup/path) for UI popups and filesystem writes

ACPC/PokerStars serialization for exports and simulations

Run the suite with `busted -v tests` (invoking busted without the tests path will not find specs).

2. Agent Mission

The mission of the AI agent is:

Implement and maintain the Neovim poker plugin.

Ensure all busted tests pass at all times.

NEVER introduce new behavior without also writing new tests.

Automatically create or update specs to cover all new or modified functionality.

Follow idiomatic Lua, Neovim plugin architecture, and the existing project conventions.

Ensure no test is flaky, ambiguous, or incomplete.

If behavior is unclear, the agent must:

Prefer writing explicit tests demonstrating the intended behavior before writing implementation code.

Expand test coverage to remove ambiguity.

3. Required Workflow (TDD Enforcement)

The agent MUST follow this process:

Step 1 — Understand Existing Code

The agent fully loads all relevant files in:

lua/poker/

after/plugin/

plugin/

tests/

The agent should consider cross-module interactions when planning changes.

Step 2 — Before Making Any Change

The agent must:

Confirm all existing tests currently pass.

If tests fail, the agent must fix the failures before adding new functionality.

Step 3 — When Adding New Behavior

The agent must:

Write or update a busted spec file first.

Ensure the test describes:

Intended new behavior

Edge cases

Any assumptions or expected model behavior

Only after tests are written, implement the minimal code needed to make them pass.

Step 4 — After Implementing the Code

The agent must:

Run the full test suite again.

Ensure 100% green with no skipped tests.

Refactor only after tests are green.

Ensure the AGENTS.md is updated to reflect any changes in the repository structure.

Ensure that README.md is updated if applicable for the change.

Step 5 — Completion Condition

The agent must only consider a task complete when:

All tests pass

Coverage for new behavior exists

No regressions introduced

The code is idiomatic Lua

The code integrates cleanly with Neovim

The repository layout remains consistent with Neovim plugin standards

4. Testing Guidelines
4.1 Where to Put New Tests

Gameplay, logic, or rules → tests/match_spec.lua
Card or deck structures → tests/cards_spec.lua
Hand evaluation ranking → tests/hand_evaluator_spec.lua
AI decisions, ranges, strategy, buckets, opponent modeling, or tuning parameters → tests/ai_spec.lua and tests/ai/*.lua
UI or rendering/layout → tests/window_spec.lua
Neovim commands/keymaps → tests/commands_spec.lua
Exports, simulators, or log parsing → tests/export/*.lua
Shared utilities/helpers → tests/utils_spec.lua
Bug regressions → extend tests/test_regression.lua with a focused failing case
Every new module must have a *_spec.lua test file.

Window specs assert popup sizing, centering, and the background dimension monitor. When editing `window.lua`, add or update tests that drive `vim._mock.trigger_autocmd("VimResized")`, `vim._mock.run_deferred()`, and `window.handle_resize()` so that resizing logic stays deterministic. Commands specs now cover using the secondary key (default `k`) to skip to the player turn; extend `tests/commands_spec.lua` whenever you change input handling or mappings.

4.2 Test Design Rules

Tests must:

Be deterministic

Avoid depending on actual Neovim except through tests/helpers/mock_vim.lua

Use pure functions where possible

Cover error conditions, edge cases, and invalid input

Assert on all expected outputs

5. Code Style & Architecture Requirements
5.1 Overall

The agent must write:

Clean, idiomatic Lua

Consistent return values

Minimal global state (prefer module tables)

Neovim-compatible plugin patterns (init.lua, exposed commands, keymaps)

5.2 Neovim Lua Conventions

Always return a module table at the end of each file

Avoid accessing vim directly in logic files; wrap through mock_vim.lua in tests

Keep UI code inside window.lua

Keep CLI commands inside commands.lua

Keep pure poker objects (cards, hands, match, ai) inside the corresponding core modules

Hook resize/zoom handling through autocmds (`VimResized`, `WinResized`, `OptionSet`) and timer-safe `vim.defer_fn` loops so `tests/helpers/mock_vim.lua` can drive them via `vim._mock.trigger_autocmd` and `vim._mock.run_deferred`.

5.3 Testability

Code should be structured so that:

All logic is testable without Neovim

Side-effects are minimal

6. Responsibilities of Each Core Module

This section ensures the agent understands the intent of every file:

cards.lua

Card representation

Deck creation & shuffling

Sorting & comparing cards

hand_evaluator.lua

Determine poker hand rank

Compare hands

Detect two-pair, flush, straight, etc.

match.lua

Represent a poker match

Players, chips, bets, pot management

Game state transitions

Turn progression

Maintain accurate event-feed text and payout logs (use `format_payout_message` so human wins read “You win …”).

ai.lua

Poker agent logic

Call/raise/fold decisions

Protect premium preflop buckets from folding for free (tests live in `tests/ai/ai_decision_spec.lua`).

ai/strategy.lua, ai/range_buckets.lua, ai/equity.lua, ai/preflop_ranges.lua, ai/opponent_model.lua

Bucket selection, board texture handling, equity estimates, and opponent modelling helpers that feed AI decisions

window.lua

Display UI inside Neovim buffer

Render match state

Handle redraw events

Manage popup sizing/centering, wrap long action text, and provide compact layouts + background dimension monitoring that reacts to `VimResized`, `WinResized`, and zoom changes.

simulator.lua

Headless AI-only simulation to generate ACPC logs and stress rules

export/acpc.lua

Serialize game definitions and match states to ACPC log lines and write log files

export/pokerstars.lua

Serialize hand histories in PokerStars format and write them to disk

parse_log.lua

CLI script to read ACPC logs and emit observed action frequencies

frequency_tracker.lua, frequency_error.lua, target_frequencies.lua, tuning_params.lua, auto_tune.lua, run_tuner.lua

Track observed frequencies, compute errors against targets, adjust tuning parameters, and orchestrate tuning runs

json.lua

Lightweight JSON encoding/decoding helper for tuning utilities

commands.lua

Expose Neovim commands like:

:PokerStartMatch

:PokerNextHand

:PokerShowWindow

The secondary keymap (`k` by default) skips waiting AI timers via `match.skip_to_player_turn()` before acting as a fold/destroy shortcut.

utils.lua

Shared helper functions

Must be pure and testable

init.lua

Entry point for the Lua module

Expose public API

plugin/mappings.lua

Keymaps (executed on plugin load)

after/plugin/poker.lua

Additional initialization after load

tests/helpers/mock_vim.lua

Deterministic shims for Neovim APIs (buffers, windows, popup borders, autocmds, timers); extend it when new editor interactions are introduced so specs can drive them.

7. Forbidden Actions

The agent MUST NOT:

Introduce behavior without tests

Delete tests without replacing them

Leave untested code paths

Introduce nondeterministic randomness (must mock RNG)

Break Neovim runtime assumptions

Modify LICENSE or README.md unless requested

Create global variables

Skip failing tests instead of fixing them

Assume access to the internet

8. PR-Style Requirements for Agent-Generated Changes

Each change must include:

Tests for new behavior

Implementation satisfying the tests

Optional small refactor, only if tests remain green

A short rationale included in the assistant message:

What changed

Why

Which tests were added

9. The Agent’s Success Criteria

The agent is successful when:

All busted tests pass

All new or modified behavior is fully tested

Code is idiomatic Lua and maintainable

The Neovim poker plugin remains fully functional

No regressions occur

No test debt accumulates
│  ├─ sim_cli_spec.lua
