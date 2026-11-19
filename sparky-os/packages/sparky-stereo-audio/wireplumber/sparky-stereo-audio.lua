-- Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/18
-- Copyright 2026 under the GNU GPL3 License
-- Per-stream insertion after the existing output policy chooses the real sink.
-- Stereo streams keep their original target. No default metadata is changed.
local lutils = require ("linking-utils")
local cutils = require ("common-utils")
local log = Log.open_topic ("s-sparky-audio")
local filters = {}
local generation = 0
local layouts = {
  ["5.1"] = { "FL", "FR", "FC", "LFE", "SL", "SR" },
  ["7.1"] = { "FL", "FR", "FC", "LFE", "RL", "RR", "SL", "SR" },
}
local angles = { FL=30, FR=330, FC=0, LFE=0, SL=110, SR=250, RL=150, RR=210 }
local hesuvi = { FL={0,1}, FR={8,7}, FC={6,13}, LFE={6,13}, SL={2,3}, SR={10,9}, RL={4,5}, RR={12,11} }
local function json (t)
  if type(t) ~= "table" then return t end
  local v = {}
  for k, value in pairs(t) do v[k] = json(value) end
  return #t > 0 and Json.Array(v) or Json.Object(v)
end
local function graph (layout, filename, kind)
  local nodes, links, inputs = {}, {}, {}
  for i, channel in ipairs(layouts[layout]) do
    if kind == "hesuvi" then
      table.insert(nodes, { type="builtin", name="copy"..channel, label="copy" })
      table.insert(inputs, "copy"..channel..":In")
      for e, ear in ipairs({"L", "R"}) do
        local name = channel..ear
        table.insert(nodes, { type="builtin", name=name, label="convolver", config={filename=filename, channel=hesuvi[channel][e]} })
        table.insert(links, { output="copy"..channel..":Out", input=name..":In" })
        table.insert(links, { output=name..":Out", input="mix"..ear..":In "..i })
      end
    else
      table.insert(nodes, { type="sofa", name=channel, label="spatializer", config={filename=filename},
        control={ Azimuth=angles[channel], Elevation=0, Radius=1.4 } })
      table.insert(inputs, channel..":In")
      for _, ear in ipairs({"L", "R"}) do
        table.insert(links, { output=channel..":Out "..ear, input="mix"..ear..":In "..i })
      end
    end
  end
  for _, ear in ipairs({"L", "R"}) do table.insert(nodes, {type="builtin", name="mix"..ear, label="mixer"}) end
  return { nodes=nodes, links=links, inputs=inputs, outputs={"mixL:Out", "mixR:Out"} }
end
local function options (name)
  local raw = Json.Raw(Settings.get_string("sparky.audio.outputs"))
  if not raw or not raw:is_object() then return {} end
  local all = raw:parse()
  return all[name] or {}
end
local function is_headphone (node, source)
  local p = node.properties
  local device_id = tonumber(p["device.id"])
  if device_id then
    local dev = source:call("get-object-manager", "device"):lookup {
      Constraint { "bound-id", "=", device_id, type="gobject" }
    }
    if dev then
      for pod in dev:iterate_params("Route") do
        local route = cutils.parseParam(pod, "Route")
        if route and route.direction == "Output" and route.device == tonumber(p["card.profile.device"]) then
          for epod in dev:iterate_params("EnumRoute") do
            local e = cutils.parseParam(epod, "EnumRoute")
            if e and e.index == route.index and e.info and e.info["port.type"] then
              return e.info["port.type"] == "headphones" or e.info["port.type"] == "headset"
            end
          end
        end
      end
    end
  end
  local form = p["device.form-factor"] or p["device.form_factor"]
  local icon = p["device.icon-name"] or p["api.bluez5.icon"]
  local profile = p["api.bluez5.profile"] or p["bluez5.profile"] or ""
  return form == "headphone" or form == "headphones" or form == "headset" or
    icon == "audio-headphones" or icon == "audio-headset" or profile:find("^headset%-head%-unit") ~= nil
end
local function channel_count (node)
  local n = tonumber(node.properties["audio.channels"])
  if n then return n end
  for pod in node:iterate_params("EnumFormat") do
    local p = cutils.parseParam(pod, "EnumFormat")
    if p and type(p.channels) == "number" then return p.channels end
  end
  return 0
end
local function release (id)
  local previous = filters[id]
  filters[id] = nil
  if previous then
    if previous.timer then previous.timer:destroy() end
    if previous.module then previous.module:unload() end
    previous.module = nil
  end
end
SimpleEventHook {
  name = "sparky-audio/binaural",
  after = { "linking/find-defined-target", "linking/find-default-target", "linking/find-filter-target" },
  before = "linking/prepare-link",
  interests = { EventInterest { Constraint { "event.type", "=", "select-target" } } },
  execute = function (event)
        local source, om, si, props, flags, target = lutils:unwrap_select_target_event(event)
        if props["media.class"] ~= "Stream/Output/Audio" or (props["node.name"] or ""):find("^sparky%.audio%.") then
          return
        end
        local node = si:get_associated_proxy("node")
        if not node then return end
        local target_node = target and target:get_associated_proxy("node")
        if not target_node then release(node.id); return end
        local tp = target_node.properties
        if (tp["node.name"] or ""):find("^sparky%.audio%.") then return end
        local opts = options(tp["node.name"])
        local count = channel_count(node)
        local headphone = is_headphone(target_node, source)
        if opts.headphones ~= nil then headphone = opts.headphones end
        if not headphone or count <= 2 or opts.enabled == false or cutils.parseBool(props["item.node.encoded-only"]) then
          release(node.id); return
        end
        local layout = opts.layout or (count > 6 and "7.1" or "5.1")
        if not layouts[layout] then event:stop_processing(); log:warning("sparky.audio.invalid-layout"); return end
        local filename = opts.hrtf or "/usr/share/libmysofa/MIT_KEMAR_normal_pinna.sofa"
        local kind = opts.kind or "sofa"
        local key = tp["node.name"]..":"..layout..":"..filename..":"..kind
        local old = filters[node.id]
        if old and old.key ~= key then release(node.id); old = nil end
        if not old then
          generation = generation + 1
          local name = "sparky.audio."..generation
          local args = {
            ["node.description"] = tp["node.description"] or tp["node.name"],
            ["filter.graph"] = graph(layout, filename, kind),
            ["capture.props"] = { ["node.name"]=name, ["media.class"]="Audio/Sink", ["node.virtual"]=true,
              ["priority.session"]=-1000, ["audio.channels"]=#layouts[layout], ["audio.position"]=layouts[layout] },
            ["playback.props"] = { ["node.name"]=name..".output", ["node.passive"]=true,
              ["node.dont-fallback"]=true, ["node.linger"]=true, ["target.object"]=tp["node.name"],
              ["stream.dont-remix"]=true, ["audio.channels"]=2, ["audio.position"]={"FL", "FR"} },
          }
          old = { name=name, key=key, module=LocalModule("libpipewire-module-filter-chain", json(args):to_string(), {}) }
          filters[node.id] = old
          if not old.module then release(node.id); event:stop_processing(); log:warning("sparky.audio.hrtf-load-failed"); return end
        end
        local filter = om:lookup { type="SiLinkable", Constraint { "node.name", "=", old.name } }
        if filter then
          flags.can_passthrough = false
          event:set_data("target", filter)
          return
        end
        -- Let node-added/create-item events register the new filter first.
        -- Holding select-target open here prevents its own new target from
        -- being registered by WirePlumber's event dispatcher.
        event:stop_processing()
        old.tries = (old.tries or 0) + 1
        if old.tries < 100 and not old.timer then
          old.timer = Core.timeout_add(20, function()
            old.timer = nil
            source:call("schedule-rescan", "linking")
            return false
          end)
        elseif old.tries >= 100 then
          log:warning("sparky.audio.hrtf-load-timeout")
        end
      end,
}:register()
SimpleEventHook {
  name="sparky-audio/release",
  interests={ EventInterest { Constraint {"event.type", "=", "node-removed"} } },
  execute=function(event) release(event:get_subject().id) end,
}:register()
Settings.subscribe("sparky.audio.outputs", function()
  local source = Plugin.find("standard-event-source")
  source:call("schedule-rescan", "linking")
end)
