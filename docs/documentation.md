# Stimulus Task Script — Explained

`stimuli_presentation.gd` runs a two-block image-naming task: participants see a
picture and respond before a timer runs out. Block 1 shows **objects**,
block 2 shows **actions**, separated by an inter-block rest interval.

## Scene assumptions

The script expects to be a sibling of these nodes (accessed via `get_parent()`):

| Node path | Purpose |
|---|---|
| `main_menu` / `main_menu/start_button` | Start screen and its button |
| `main_menu/difficulty_hbox/option_button` | Difficulty selector (its `selected` index is used as a folder name) |
| `inter_block_int` / `inter_block_int/vbox/advance_button` | Rest-interval screen |

The script's own node needs a child `Sprite` to display the current image.

## Task flow

```
main menu → [start_button] → BLOCK 1 (objects)
                                  │ block timer expires
                                  ▼
                         inter-block interval (rest)
                                  │ interblock timer expires
                                  ▼
                             BLOCK 2 (actions)
                                  │ block timer expires
                                  ▼
                              main menu
```

`block1` (bool) tracks which block is active and is stored with every trial.

## Trial loop

1. `change_texture()` starts a trial: records `trial_start_timestamp`, then
   calls `_change_texture()`.
2. `_change_texture()` picks a random image from `image_paths` (removing it
   so it won't repeat), displays it via `load_texture()`, and starts two
   things in parallel:
   - `freeze_change()` — a short `rsp_freeze_time` window where input is
     ignored, so a leftover key press from the previous trial can't be
     counted as a response to the new image.
   - `next_image_timer()` — the response deadline. If it fires first, the
     trial is scored as a failure and the task moves on automatically.
3. If the participant presses `ui_accept` while not frozen, the response is
   scored a success, the trial is saved, and the next trial starts
   immediately.
4. When `image_paths` runs out, `change_texture()` reloads the pool from
   disk via `start_block_images()` before continuing (repeating the same images).

## Timers

| Timer | Duration | On expiry |
|---|---|---|
| `image_presentation_timer` | `image_presentation_max_duration - rsp_freeze_time` | trial → failure, next image |
| `block_timer` | `block_duration` minutes | current block ends |
| `interblock_timer` | `interblock_time` seconds | block 2 starts |

## Stimuli folders

Images live under:

```
/imagens/<difficulty_index>/<objects|actions>/
```

`difficulty_index` comes from the option button's `selected` property. It can be 0 (easy), 1 (medium) or 2 (difficult)
`get_dir_contents()` recursively walks that folder (via `DirAccess`,
skipping `.import` files) and returns every file path found; `_add_dir_contents()`
is the recursive helper, since Godot's directory iterator only walks one
level per call.

## Data logging

Every trial is appended to the `answers` dictionary as five parallel arrays
(`block1`, `trial_start`, `trial_end`, `image`, `success` — same index =
same trial). After each trial, `save()` overwrites a JSON file at:

```
user://aphasia_stim_registration_<task_start_unix_time>.json
```

Rewriting the whole file each time means at most one trial's data is at
risk if the app closes unexpectedly.

## Console logging

All runtime logs are prefixed `[StimulusTask]` (via the `_log()` helper) so
they're easy to filter. Key events logged: task/block/trial start and end,
image selection, pool reloads, and save results. Failures that used to be
silent now surface explicitly:

- **`get_dir_contents()`** — errors if the folder can't be opened, warns if
  it's empty.
- **`load_texture()`** — errors if the file can't be opened or the
  image fails to decode, instead of silently showing nothing/garbage.
- **`save()`** — errors if the JSON file can't be opened for writing,
  instead of silently losing trial data.

Set `VERBOSE_FILE_SCAN = true` at the top of the script to additionally log
every file/folder visited while scanning for stimuli (useful only when
tracking down a missing-image problem — otherwise very noisy).

## Known loose end

`change_image` is set to `true` in `freeze_change()` but isn't read anywhere
else in this script. It may be polled from another script, or it may be
dead code — worth checking before removing it.

## Input actions used

- `ui_cancel` — Esc — quit the application
- `ui_accept` — Enter/Space — register a response (during a trial)
- `ui_focus_next` — Tab — abort the current block and return to the main menu

These are mapped in **Project Settings → Input Map**.