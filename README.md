# Poker.nvim

Poker.nvim brings a fully playable No-Limit Texas Hold'em table to your Neovim session. Launch a popup, battle multiple AI opponents with realistic side-pot logic, log every hand for later study, and plug in your own poker bot without leaving your editor.

Aside from this line, this project was built entirely using AI coding agents, so expect to encounter the occasional bug.

## Feature Highlights

- Terminal-native table with rotating dealer button, timers, and an event feed that mirrors casino-style log lines.
- Automated bankroll persistence, showdown summaries, and optional ACPC + PokerStars export files.
- Multi-way side pots, configurable blinds/stacks/opponent counts, and adaptive AI that understands position, pot odds, and blind sizes.
- Pluggable AI entry point plus a simulator/tuning pipeline for generating datasets and adjusting strategy heuristics.
- Neovim-friendly UX: buffer-local keymaps, command palette integration, highlight groups, and persistent settings via `setup()`.

## Requirements

- [Neovim](https://github.com/neovim/neovim) >= 0.5.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

### lazy.nvim

```lua
return {
  {
    'cmbilly8/poker.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('poker').setup()
    end,
  },
}
```

### Packer

```lua
use {
  'cmbilly8/poker.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
}
```

### vim-plug

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'cmbilly8/poker.nvim'
```

## Quick Start

```lua
require('poker').setup({
  suit_style = 'black',       -- 'black' or 'white'
  starting_stack = 1000,      -- table stakes for each seat
  small_blind = 10,           -- forced small blind posted each hand
  big_blind = 20,             -- forced big blind posted each hand
  ai_opponents = 6,           -- number of computer seats (defaults to 6)
  scores_path = nil,          -- defaults to stdpath('data') .. '/pokerscores.json'
  enable_exports = false,     -- opt-in; never writes to disk unless true
  export_acpc_path = nil,     -- defaults to stdpath('data') .. '/poker/acpc.log'
  export_pokerstars_dir = nil,
  keybindings = {
    primary = 'j',            -- advance / check / call
    secondary = 'k',          -- fold / skip AI timers / start the next hand
    bet = 'l',                -- prompt for a bet/raise amount on your turn
    quit = 'q',               -- quit the table
    stats = ';',              -- toggle the stats popup
  },
})
```

- Run `:Poker` (or `:PokerPrimary`) to sit down immediately.
- Player results are saved to `stdpath('data')/pokerscores.json` unless you override `scores_path`.
- When exports are enabled Poker.nvim writes ACPC logs to `stdpath('data')/poker/acpc.log` and PokerStars hands to `stdpath('data')/poker/pokerstars/`. Both paths are customizable per-setting above.

## Popup Commands

| Command | Description |
| --- | --- |
| `:Poker` | Create the popup table and deal a fresh hand. |
| `:PokerPrimary` | Context-sensitive "go" action: jump AI timers, check/call, or start the next hand. |
| `:PokerSecondary` | Fold during a hand, skip directly to your next decision during AI turns, or start the next hand once the hand ends. |
| `:PokerBet` | Prompt for a bet/raise amount on your action. |
| `:PokerStats` | Toggle the stats popup. |
| `:PokerResetStats` | Reset the persisted stats. |
| `:PokerQuit` | Close the popup immediately. |
| `:PokerResetScores` | Delete the persisted scoreboard file. |

### Default Keymaps Inside the Popup

| Key | Action |
| --- | --- |
| `j` | Primary action / acknowledge prompts. |
| `k` | Secondary action (`:PokerSecondary`) — fold, skip AI timers, or start the next hand. |
| `l` | Bet/raise prompt. |
| `;` | Toggle the stats popup. |
| `q` | Quit the table buffer. |

All mappings are buffer-local and can be replaced through `setup()` or `require('poker').set_keybindings()`.

When the stats popup is open, press `r` to reset the persisted stats.

## Highlight Groups

Customize the popup colors by overriding these highlight groups in your config:

- `PokerWindow` — popup border/title highlight.
- `PokerStatusFold` / `PokerStatusCheck` / `PokerStatusBet` / `PokerStatusCall` / `PokerStatusWin` — action text inside the table/event feed.
- `PokerCardRed` — hearts/diamonds suit glyphs.
- `PokerPlayerWinBorder`, `PokerPlayerFoldBorder`, `PokerPlayerActiveBorder` — player card frame outlines for winners, folds, and the seat currently acting.

Example:

```vim
hi PokerStatusWin guifg=#00ff9d
hi PokerPlayerActiveBorder gui=bold guifg=#f2c94c
```

All highlight groups are created lazily the first time the table renders, so set overrides during startup.

## Gameplay Flow

1. Seats post blinds based on your config (any blind size is supported).
2. Hole cards are dealt, followed by flop/turn/river streets with intermediate betting rounds.
3. The event feed records every action (deals, checks, bets, folds, showdown reveals).
4. Side-pot aware payouts handle multi-way all-ins correctly and log who won each portion.
5. Completed hands increment your local scoreboard and optionally export to ACPC/PokerStars formats.

## Table Snapshot

```
┌ Poker.nvim — 6-Max Cash Table ┐
│ Seat BTN (You)   1450 ⋅ raises to 120 │
│ Seat SB          880  ⋅ calls        │
│ Seat BB          1100 ⋅ folds        │
│ Board: [Ac][Jh][8c]  Pot: 370        │
│                                             │
│ Event Feed                                    │
│ • New hand #184          • BTN dealt Ah Qc    │
│ • SB posts 10            • BB posts 20        │
│ • BTN raises to 120      • SB calls 120       │
└──────────────────────────────────────────────┘
```

Screenshots/GIFs captured from a live Neovim session look just like the mock above—open an issue or PR if you'd like to contribute additional artwork.

## Scores, Logs & Exports

- **Scores** — stored as JSON at `stdpath('data')/pokerscores.json`. Customize via `scores_path` or call `:PokerResetScores` to clear.
- **Event feed** — scrollable right-hand pane that mirrors the serialized action order. Messages include blind posts, bets, folds, showdowns, and payout summaries.
- **Exports** — disabled by default. When `enable_exports=true`, files land in `stdpath('data')/poker/` unless you override `export_acpc_path` / `export_pokerstars_dir`. You can also register `match.set_on_hand_complete` hooks to stream the serialized data elsewhere (e.g., remote services or analytics).

## AI Overview

The stock AI reads a rich state payload (`seat`, `position`, blind sizes, pot odds, raise history, opponent stack sizes) and chooses from fold/check/call/bet actions using:

- Preflop range buckets tuned for different positions and stack depths.
- Board-texture-aware heuristics for continuation betting, semi-bluffing, and showdown value.
- Opponent modeling hooks that adapt frequencies over time (see `lua/poker/ai/*`).

You can override `require('poker.ai').decide` with your own logic, or plug in whole modules that reference helper APIs such as `poker.match.get_state(player)` and `poker.match.available_actions(player)`.

## Simulation & Tuning

Poker.nvim ships helper scripts so you can run AI-vs-AI simulations outside Neovim, parse the resulting ACPC logs, and automatically retune `lua/poker/tuning_params.lua`.

### Requirements

- A system `lua` interpreter (5.1+ works; LuaJIT is fine).
- This repository cloned locally so `lua` can set `package.path` to `./lua`.
- Optional: `busted` to rerun the suite between iterations.

### Step 1 — Generate ACPC Logs

```bash
./scripts/run_simulator.sh
```

The script seeds `tests/helpers/mock_vim`, runs `poker.simulator.run`, and writes a log under `data/sim/` (override `hands`, `players`, or `acpc_path` via flags, e.g. `./scripts/run_simulator.sh --hands 500 --players 5 --acpc-path data/sim/custom.log`). For long sessions or custom binaries run `./run_batch.sh --iterations 25` to loop the workflow multiple times.

### Step 2 — Parse Logs into Frequencies

```bash
lua lua/poker/parse_log.lua path/to/acpc.log
```

This produces two JSON files in the repo root:

- `observed_freq.json` — raw action counts per street (`open`, `call`, `fold`, `raise`, plus totals).
- `analysis.json` — normalized percentages for each action along with the same `total` counts. Use this for quick sanity checks or to visualize drift versus your target ranges.

These files (and any snapshots in `tuning_history/`) are ignored by git so they never pollute commits; delete them whenever you want to start fresh.

### Step 3 — Update Tuning Parameters

```bash
lua lua/poker/run_tuner.lua
```

The tuner reads `observed_freq.json`, compares it against `lua/poker/target_frequencies.lua`, and rewrites `lua/poker/tuning_params.lua`. It also appends a snapshot to `tuning_history/iter_XXXX.json` (set the `TUNER_ITER` env var before running to control the suffix). Commit the updated tuning params if the new frequencies pass your acceptance thresholds.

### Step 4 — Interpret & Iterate

- Compare `analysis.json` vs `lua/poker/target_frequencies.lua` to see which streets overshoot or undershoot desired aggression.
- Use `observed_freq.json` to confirm sample sizes (`total` column) before drawing conclusions.
- Re-run `scripts/run_simulator.sh` (or your own simulator) with updated params and repeat until the deltas fall within tolerance.

These utilities never touch user data—everything lives inside the repository so you can delete the generated files between experiments or add them to `.gitignore`.

## Extensibility Hooks

- `poker.match.get_board()`, `get_players()`, `get_my_cards()` — read-only snapshots for bots or UI integrations.
- `poker.match.available_actions(player)` — determine legal moves before submitting commands.
- `poker.window` — exposes drawing helpers if you need to skin the popup differently.
- `poker.export.*` — ACPC and PokerStars serializers that can be reused in custom pipelines.

## License

Poker.nvim is distributed under the terms of the MIT License. See [LICENSE](LICENSE) for details.
