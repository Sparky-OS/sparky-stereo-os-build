-- Created by Daniel Ramos (Capitain Jack) and Paweł "pavroo" Pijanowski 2026/11/07
-- Copyright 2026 under the GNU GPL3 License
-- A newly connected headset or speaker takes the sound and hands it back when it leaves (ORDER 129; Daniel, 2026-11-07: "speakers as well").
-- WirePlumber's default-nodes hooks give the sink the person chose (default.configured.audio.sink) 30000 more priority and skip
-- the best-node search when a node above 15000 is already selected, so a new device never wins by its own priority. This hook runs
-- before find-selected-default-node and selects the newest connected output above that. It changes only the live default
-- (default.audio.sink, as apply-default-node does) and never writes the person's choice: when the output goes, the next
-- select-default-node finds the chosen sink again by itself.
-- Eligible: a Bluetooth audio sink (bluez_output.*) and a USB audio output (device.bus usb), headset, speaker or sound card alike.
-- "Newly connected": a sink that appears in the first GRACE seconds after WirePlumber starts (a desk DAC at boot, a headset already
-- connected) is not new and never moves the default; the same sink plugged in later is, and is again after it left.
-- The person's switch: setting sparky.new-output-takes-the-sound (README, "A newly connected headset or speaker").

local log = Log.open_topic ("s-sparky-new-output")

local GRACE = 10
local started = os.time ()
local present = {}   -- sinks that were there when WirePlumber started

local function eligible (p)
  local name = p["node.name"] or ""
  return name:find ("^bluez_output%.") ~= nil or p["device.bus"] == "usb"
end

SimpleEventHook {
  name = "sparky-stereo/new-output-seen-at-start",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink", type = "pw-global" },
    },
  },
  execute = function (event)
    if os.time () - started < GRACE then
      local name = event:get_subject ().properties ["node.name"]
      if name then
        present [name] = true
      end
    end
  end
}:register ()

SimpleEventHook {
  name = "sparky-stereo/new-output-takes-the-sound",
  before = "default-nodes/find-selected-default-node",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-default-node" },
    },
  },
  execute = function (event)
    local props = event:get_properties ()
    if props ["default-node.type"] ~= "audio.sink" then
      return
    end
    local available = event:get_data ("available-nodes")
    available = available and available:parse ()
    if not available then
      return
    end
    -- forget the sinks that left, so that one plugged in again later is new
    local here = {}
    for _, np in ipairs (available) do
      here [np ["node.name"]] = true
    end
    for name in pairs (present) do
      if not here [name] then
        present [name] = nil
      end
    end
    if not Settings.get_boolean ("sparky.new-output-takes-the-sound") then
      return
    end
    local best, best_serial
    for _, np in ipairs (available) do
      local name = np ["node.name"]
      if np ["media.class"] == "Audio/Sink" and eligible (np) and not present [name] then
        local serial = tonumber (np ["object.serial"]) or 0
        if best == nil or serial > best_serial then
          best, best_serial = name, serial
        end
      end
    end
    if best then
      log:info ("new output " .. best .. " takes the sound")
      event:set_data ("selected-node-priority", 50000)
      event:set_data ("selected-node", best)
    end
  end
}:register ()
