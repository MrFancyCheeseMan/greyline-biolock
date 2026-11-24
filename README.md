# Greyline Biolock

Combine-style biometric door lock for a custom Garry's Mod gamemode. The
scanner uses the gamemode's existing faction system; only Combine players
(plus an admin override) can unlock a door it is attached to.

## Install

1. Copy this folder to `garrysmod/addons/greyline-biolock/`.
2. Restart the server (autorun files only load at startup).
3. Obtain a lock with `greyline_biolock_give` (the engine's `give` command only
   exists in sandbox). If the gamemode exposes `Greyline.Inventory.Provision`,
   the lock is added as an inventory item; otherwise the standalone SWEP is
   given. `greyline_biolock_place` remains a console fallback while aiming at a
   door.
4. With the inventory item, aim at a door, open your belongings, hover the
   Biolock (`Use`) and left-click it. With the SWEP, primary fire attaches it.
5. Remove a lock with the tool's secondary fire or `greyline_biolock_remove`.

No workshop content is required. The default biolock model
(`models/props_combine/combine_lock01.mdl`) and sounds ship with HL2/GMod; all
paths are configurable via convars.

## Faction integration

`Biolock.GetPlayerFaction(ply)` in `lua/autorun/greyline_biolock_config.lua`
reads, in order:

1. `ply.GLFaction` (temporary override)
2. `ply.GLCharacter.faction` (persisted character)
3. `ply:GetNWString("gl_faction")`
4. `ply:GetFaction()` if present

If your gamemode uses a different API, override that one function. Do not
add a second faction system.

> **Greyline caveat:** the current showcase code's `normalizeCharacterFaction()`
> unconditionally resets `faction` to `civilian`. Until that is fixed, no player
> will report as Combine and every scan will be denied. Set `ply.GLFaction` to
> `"combine"` when testing, or fix the helper first.

## How it works

1. The tool traces from the server-side player eye to a door-class entity. The
   aim point must be near the handle edge; aiming at the door centre is rejected.
2. `Biolock.Create` snaps the scanner to the handle edge, parents it to the door
   (so it follows
   every open/close), calls `Fire("Lock")`, and pins the door's movetype to
   `MOVETYPE_NONE` so it cannot be physgunned or pushed open.
3. `PlayerUse`, `PhysgunPickup` and `GravGunPickupAllowed` hooks reject the
   locked door for everyone. `EntityTakeDamage` blocks damage unless the device
   is configured destroyable.
4. `ENT:Use` performs **the only** permission check, serverside. Denied players
   get a red HUD banner and beep; allowed players get a 1.2s blue pulse.
5. On success the door is unlocked and the scanner turns green. It stays
   unlocked until an authorized player clicks the scanner again to re-lock it;
   there is no automatic re-lock timer.
6. `OnRemove` always unlocks the door first, including when the scanner is
   destroyed, the door is removed, or the map changes.
7. **Double doors:** one scanner covers both leaves. The server pairs adjacent
   doors (same targetname, or nearest same-plane leaf within
   `greyline_biolock_double_door_range`, default 96). Lock/unlock affects both
   sides; a second scanner on the bare leaf is rejected. Range `0` disables it.

**No client-to-server net message exists.** The only net string is
server-to-client feedback.

## Configuration

All tunables are in `lua/autorun/greyline_biolock_config.lua`; convars use the
`greyline_biolock_` prefix. See the `Biolock.Convars` table for names/defaults.
`handle_inset` (10) and `handle_band` (18) snap the lock to the handle edge and
control how close you must aim; `handle_right`/`handle_down` are deprecated.
`handle_out` (4) lifts it off the door face. `model_yaw_offset` (-90) turns `combine_lock01`'s +Y face straight out of the door
(pitch/roll stay zero); `light_offset` (`0 8 -6`) moves the status glow onto the
model's circular light. `double_door_range` (96) pairs the two leaves of a double
door; set it to `0` to disable. `relock_delay` is deprecated and ignored.

## Testing checklist

Use this checklist:

- Non-Combine: Use the scanner -> red "ACCESS DENIED", door stays locked.
- Combine: Use the scanner -> blue progress -> green "ACCESS GRANTED", door opens.
- Superadmin: same as Combine even with faction set to civilian.
- Try `+use`, physgun, gravity gun and crowbar on the locked door -> all blocked.
- Remove the scanner while locked -> door unlocks.
- Disconnect mid-scan -> scan cancels, no unlock.
- Place on a wall -> "INVALID SURFACE". Aim at door centre -> "AIM AT THE DOOR
  HANDLE". Place twice -> "LOCK ALREADY PRESENT".
- Set `greyline_biolock_persist 1`, change map -> locks restore.
