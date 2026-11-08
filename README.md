# Stormworks CIWS (in-game) — Build & Wiring Guide

`cwis.lua` is a Lua script for a **Stormworks microcontroller**. It reads radar and
physics-sensor values, picks the closest target, applies a lead estimate, and outputs
turret aim angles plus a fire-enable signal. This is for the Stormworks game only.

This README describes **exactly what the script reads and writes**, channel by channel.
Anything the script does *not* do (pivot control, signal routing) is marked as
something you must build yourself.

> ⚠️ **Read [Known issues](#7-known-issues-in-the-current-script) before building.**
> The current channel layout has overlaps, so a straight "plug the radar composite in"
> build will not work as-is. The README documents the code as written, it does not fix it.

---

## 1. Two kinds of wiring

| Term | Where you do it | What it means here |
|------|-----------------|--------------------|
| **External wiring** | On the vehicle, in the build editor | Logic links between physical blocks (radars, physics sensor, pivots, gun) and the microcontroller's input/output nodes. |
| **Internal wiring** | Inside the microcontroller editor | Links between the microcontroller's input/output nodes and the **Lua script block**. |

The Lua block has **one composite input** and **one composite output**. Everything the
script reads comes from that one input composite; everything it writes goes out on that
one output composite. A composite carries number channels 1–32 and on/off (bool)
channels 1–32 at the same time.

---

## 2. What the script reads (Lua block composite INPUT)

### Number channels

| Channel | Variable | Expected meaning | Unit |
|---------|----------|------------------|------|
| 1, 5, 9, 13, 17, 21, 25, 29 | `d` (target 1–8) | Track radar: distance to target *i* | metres |
| 2, 6, 10, 14, 18, 22, 26, 30 | `az` (target 1–8) | Track radar: azimuth of target *i* | turns (1 turn = 360°) |
| 3, 7, 11, 15, 19, 23, 27, 31 | `el` (target 1–8) | Track radar: elevation of target *i* | turns |
| 4, 8, …, 32 | — | **Not read** | — |
| 5, 6, 7 | `posX, posY, posZ` | Physics sensor: world position | metres |
| 8, 9, 10 | `eulX, eulY, eulZ` | Physics sensor: Euler orientation | radians (passed straight to `math.cos/sin`) |
| 11, 12, 13 | `ownVx, ownVy, ownVz` | Physics sensor: own velocity | m/s (subtracted from a **world-frame** target velocity) |
| 15, 16 | `searchAz, searchEl` | Search radar: azimuth / elevation | turns |
| 18, 19 | `upAz, upEl` | Upward radar: azimuth / elevation | turns |
| 20 | `time` | Optional sweep clock (any increasing number) | free unit; sweep = `sin(time*0.4)*0.4` |

Track-radar slot *i* (i = 0…7) uses channels `1+4i`, `2+4i`, `3+4i`.
A slot counts as a valid target only if `50 < distance < 15000` (`MIN_RANGE`, `MAX_RANGE`).
The track radar's per-target "detected" bools are **not** read; only distance matters.

### Bool channels

| Channel | Variable | Expected meaning |
|---------|----------|------------------|
| 2 | `searchFound` | Search radar has a target |
| 3 | `upFound` | Upward radar has a target |

Notice the overlaps in the number table (e.g. channel 5 is both "track target 2 distance"
and "physics X"). See [Known issues](#7-known-issues-in-the-current-script).

---

## 3. What the script writes (Lua block composite OUTPUT)

| Channel | Type | Meaning | Unit / values |
|---------|------|---------|---------------|
| Number 1 | number | Yaw (azimuth) command | turns |
| Number 2 | number | Pitch (elevation) command | turns |
| Number 3 | number | Mode (debug) | `0` idle sweep, `1` slew, `2` track |
| Number 4 | number | Distance of closest track-radar target (debug) | metres; a huge value (`math.huge`) when none |
| Bool 1 | on/off | Fire enable | on only in mode 2 when the safety checks pass |
| Bool 2 | on/off | Track filter valid (debug) | — |

What Number 1 / Number 2 contain depends on the mode:

| Mode | When | Number 1 / Number 2 | Bool 1 |
|------|------|---------------------|--------|
| 2 Track | any track-radar slot valid | Lead aim angle, relative to the **physics sensor's** forward/right/up axes | `aimAz` within `SAFE_AZ_MIN..SAFE_AZ_MAX` **and** range ≥ `MIN_FIRE_RANGE` |
| 1 Slew | no track target, upward radar found (priority) or else search radar found | That radar's raw azimuth/elevation, in **that radar's** own frame | off |
| 0 Idle | nothing found | `sin(time*0.4)*0.4` / constant `0.05` | off |

Important: these are **target angles**, not pivot speeds. The script contains no pivot
controller.

---

## 4. Build steps (in order)

1. **Turret:** a yaw pivot, a pitch pivot on top of it, the gun on the pitch pivot.
2. **Track radar:** on the pitch stage, pointing exactly where the gun points.
3. **Physics sensor:** on the turret next to the track radar, facing the same direction as
   the gun (the script treats the sensor's forward axis as "azimuth 0, elevation 0").
   Because the sensor moves with the turret, track-mode angles are **relative to where the
   turret currently points** (an error angle), not absolute pivot positions.
4. **Search radar:** fixed to the hull. **Upward radar:** fixed, tilted up.
5. **Microcontroller:** paste `cwis.lua` into a Lua block. Add one composite input node and
   one composite output node and connect them to the Lua block (internal wiring).
6. **Build the input composite** (external wiring, plus composite write blocks inside the
   microcontroller if you route individual signals) so each value lands on the channel in
   section 2.
7. **Edit the constants** at the top of `cwis.lua` (section 5).
8. **Use the outputs:** build your own yaw/pitch controller (e.g. a P or PID controller
   driving velocity pivots) from Number 1 / Number 2, and gate the gun's trigger with Bool 1.
9. Power everything and test (section 6).

### Example signal paths

- Track radar target 1 distance → input number 1 → `d` for slot 0 → closest-target pick →
  world position via physics sensor → filter → lead → output Number 1/2.
- Search radar "found" → input bool 2 → (if no track target and no upward target) mode 1
  → search radar azimuth (input number 15) copied to output Number 1.

---

## 5. Constants to set (top of `cwis.lua`)

| Constant | Default | Meaning |
|----------|---------|---------|
| `PROJECTILE_SPEED` | 800 | Your gun's muzzle velocity, m/s (no drop/drag modelled) |
| `MAX_LEAD_TIME` | 8 | Cap on lead time, s |
| `FILTER_ALPHA` / `FILTER_BETA` | 0.35 / 0.12 | Alpha-beta filter gains; lower = smoother, slower |
| `MIN_RANGE` / `MAX_RANGE` | 50 / 15000 | Valid track-radar distance window, m |
| `MIN_FIRE_RANGE` | 40 | No fire below this range, m |
| `SAFE_AZ_MIN` / `SAFE_AZ_MAX` | −0.30 / 0.30 | Allowed fire azimuth, turns, **relative to the physics sensor** |

`DT` is fixed at 1/60 s (one tick).

---

## 6. Testing & troubleshooting

Wire output Number 3, Number 4 and Bool 2 to dials/lamps so you can watch them.

| Symptom | Check |
|---------|-------|
| Mode stays 0 | Bools 2/3 not arriving; track-radar distances outside 50–15000 m |
| Mode jumps to 2 with no real target | Another signal (physics, search, upward) is landing on a track-radar channel (see known issues) |
| Idle sweep doesn't move | Nothing on number 20 (unwired = 0, so output stays 0) |
| Aim is mirrored/rotated | Physics sensor orientation; Euler order/sign assumptions |
| Turret oscillates | Your pivot controller gains (not in this script) |
| Shots behind / ahead | Raise / lower `PROJECTILE_SPEED` |

---

## 7. Known issues in the current script

These need a decision/fix in the code; this README does not change the Lua.

1. **Channel overlap (blocking).** The track-radar loop reads numbers 1–31, which collide
   with physics sensor (5–13), search radar (15–16) and upward radar (18–19). Any physics
   value between 50 and 15000 on channels 5/9/13 (e.g. world position, which is often large)
   is treated as a target distance. To use it as written, the track radar must not share
   the composite, or the code must be changed (e.g. limit the radar loop to fewer targets
   or move other inputs to channels 4/8/12/… or to a second input).
2. **Bool overlap.** If the track radar composite is fed in directly, its per-target bools
   occupy bools 1–8, which collide with bools 2 and 3.
3. **Physics sensor layout is assumed.** The script needs position on 5–7, Euler on 8–10,
   velocity on 11–13. Whether a raw physics-sensor composite already has that layout was
   not verified here; remap if needed. The script also assumes the velocity is in the
   world frame and the Euler angles are in radians with its own rotation order.
4. **Mixed frames in mode 1.** Slew uses search/upward radar angles in those radars'
   frames, while track mode outputs angles relative to the turret-mounted physics sensor.
   The two are not converted into the same reference, so a single pivot controller will
   behave differently between modes.
5. **Self-fire check is azimuth-only** and relative to the turret sensor, not the hull.
   There is no elevation limit.
6. **Lead ignores gravity and drag.**
