# Stormworks Complete CIWS Build Guide

Automatic dual-radar (search + track + upward) CIWS with closest-target priority, ballistic lead, orientation compensation, and self-fire protection.

---

## 1. Turret Structure

1. Place a **velocity pivot** (yaw) on the boat.
2. Place a second **velocity pivot** (pitch) on top of the yaw pivot.
3. Attach your gun(s) to the pitch pivot.
4. Ensure the turret can elevate high enough (ideally close to 80–90°).

---

## 2. Radars

Mount three radars:

| Radar | Mounting | Mode | FOV | Purpose |
|-------|----------|------|-----|---------|
| **Track radar** | On the turret, aligned with the guns | Static | Very small (long range) | Precise tracking + lead |
| **Search radar** | Fixed to the boat (not on turret) | Sweep or Rotation | Wider (0.1–0.2) | Find targets around the boat |
| **Upward radar** | On the turret or high on the boat, tilted upward (~60–80°) | Static or limited sweep | Medium-wide | Detect targets above |

- Use **Phalanx** or **Basic** radars.
- Power all three radars.

---

## 3. Sensors

- Place a **Physics sensor** as close as possible to the track radar.
  - Big arrow = forward (same direction as the guns)
  - Small arrow = right
- Optional: a second physics sensor at the boat’s center for more advanced self-fire checks later.

---

## 4. Microcontroller

1. Add a **Microcontroller**.
2. Open the Lua editor and paste the complete CIWS Lua script.
3. Add the required input/output nodes (see wiring section below).

---

## 5. Wiring

### Track radar
- Composite output → Microcontroller (channels 1–32)

### Search radar
- Target found (bool) → Bool input 2
- Azimuth → Number input 15
- Elevation → Number input 16

### Upward radar
- Target found (bool) → Bool input 3
- Azimuth → Number input 18
- Elevation → Number input 19

### Physics sensor
- Composite → Number inputs 5–13 (position, Euler angles, velocity)

### Optional
- A counter or timer → Number input 20 (for the idle sweep)

### Outputs
- Number 1 (yaw) → Yaw pivot controller
- Number 2 (pitch) → Pitch pivot controller
- Bool 1 (fire) → Gun fire input

---

## 6. Pivot Control

### Velocity pivots (recommended)
- Use a simple proportional controller or PID.
- Error = Lua aim angle − current pivot angle.
- Output of the controller → velocity pivot.

### Robotic pivots
- Multiply the Lua output by 4 before sending it to the pivot.

---

## 7. Configuration Checklist

- [ ] Track radar = Static, small FOV
- [ ] Search radar = Sweep/Rotation, wider FOV
- [ ] Upward radar = tilted upward
- [ ] Physics sensor orientation correct
- [ ] `PROJECTILE_SPEED` set to your gun’s velocity
- [ ] `SAFE_AZ_MIN` / `SAFE_AZ_MAX` adjusted so the turret cannot shoot the boat
- [ ] Electricity connected to everything

---

## 8. Testing

1. Spawn a target in front of the boat → turret should track and lead.
2. Spawn a target behind → turret should not fire (angle limit).
3. Spawn a high / overhead target → upward radar should detect it and slew the turret.
4. Spawn multiple targets → it should always prefer the closest one.
5. Move the boat and lean it → tracking should stay stable.

---

## 9. Tuning Tips

- Too much jitter → lower `FILTER_ALPHA` and `FILTER_BETA`.
- Shots land behind the target → increase `PROJECTILE_SPEED`.
- Shots land in front → decrease `PROJECTILE_SPEED`.
- Turret sweeps too fast/slow when idle → change the `0.4` and `0.4` values in the sweep line.

---

## Input Wiring Reference

| Channel | Source |
|---------|--------|
| Numbers 1–32 | Track radar composite |
| Bool 2 | Search radar “target found” |
| Number 15–16 | Search radar azimuth / elevation |
| Bool 3 | Upward radar “target found” |
| Number 18–19 | Upward radar azimuth / elevation |
| Numbers 5–13 | Physics sensor (pos, euler, velocity) |
| Number 20 | Time / counter for sweep (optional) |

## Outputs

| Output | Use |
|--------|-----|
| Number 1 | Yaw aim |
| Number 2 | Pitch aim |
| Bool 1 | Fire enable (includes angle limit) |
| Number 3 | Current mode (debug) |

---

Once wired and configured, the system will automatically search, slew, track the closest target, lead it, and refuse to fire through the boat — including overhead threats.
