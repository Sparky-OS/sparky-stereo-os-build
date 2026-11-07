-- Created by Daniel Ramos (Capitain Jack) and Paweł "pavroo" Pijanowski 2026/11/07
-- Copyright 2026 under the GNU GPL3 License
-- A newly connected headset takes the sound and hands it back when it leaves (ORDER 129).
-- WirePlumber's default-nodes hooks give the sink the person chose (default.configured.audio.sink) 30000 more priority and skip
-- the best-node search when a node above 15000 is already selected, so a new device never wins by its own priority. This hook runs
-- before find-selected-default-node and selects the connected headset above that. It changes only the live default
-- (default.audio.sink, as apply-default-node does) and never writes the person's choice: when the headset goes, the next
-- select-default-node finds the chosen sink again by itself.
-- A headset is a Bluetooth audio sink (bluez_output.*) or a USB sound card whose form factor is headset, headphone or hands-free.
-- The person's switch: setting sparky.headset-takes-the-sound (README, "A newly connected headset").

local log = Log.open_topic ("s-sparky-headset")

local function is_headset (p)
  local name = p["node.name"] or ""
  if name:find ("^bluez_output%.") then
    return true
  end
  local ff = p["device.form-factor"]
  return p["device.bus"] == "usb" and (ff == "headset" or ff == "headphone" or ff == "hands-free")
end

SimpleEventHook {
  name = "sparky-stereo/headset-takes-the-sound",
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
    if not Settings.get_boolean ("sparky.headset-takes-the-sound") then
      return
    end
    local available = event:get_data ("available-nodes")
    available = available and available:parse ()
    if not available then
      return
    end
    local best, best_serial
    for _, np in ipairs (available) do
      if np ["media.class"] == "Audio/Sink" and is_headset (np) then
        local serial = tonumber (np ["object.serial"]) or 0
        if best == nil or serial > best_serial then
          best, best_serial = np ["node.name"], serial
        end
      end
    end
    if best then
      log:info ("headset " .. best .. " takes the sound")
      event:set_data ("selected-node-priority", 50000)
      event:set_data ("selected-node", best)
    end
  end
}:register ()
