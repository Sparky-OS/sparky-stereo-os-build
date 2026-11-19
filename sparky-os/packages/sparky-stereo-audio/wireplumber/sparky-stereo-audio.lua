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
-- Passive split-rear matrix, following Steve Davies' MPlayer surround
-- decoder coefficients. It has crosstalk; it is not an active steering decoder.
local function matrix_graph (positions)
  local nodes = {
    {type="builtin", name="L", label="copy"}, {type="builtin", name="R", label="copy"},
    {type="builtin", name="FL", label="mixer", control={["Gain 1"]=0.707}},
    {type="builtin", name="FR", label="mixer", control={["Gain 1"]=0.707}},
    {type="builtin", name="SL", label="mixer", control={["Gain 1"]=0.5878,["Gain 2"]=-0.3928}},
    {type="builtin", name="SR", label="mixer", control={["Gain 1"]=0.3928,["Gain 2"]=-0.5878}},
  }
  local links = {
    {output="L:Out",input="FL:In 1"}, {output="R:Out",input="FR:In 1"},
    {output="L:Out",input="SL:In 1"}, {output="R:Out",input="SL:In 2"},
    {output="L:Out",input="SR:In 1"}, {output="R:Out",input="SR:In 2"},
  }
  for _, side in ipairs({"SL","SR"}) do
    table.insert(nodes, {type="builtin", name=side.."lp", label="bq_lowpass", control={Freq=7000,Q=0.70710678}})
    table.insert(nodes, {type="builtin", name=side.."delay", label="delay", config={["max-delay"]=1}, control={["Delay (s)"]=0.02}})
    table.insert(links, {output=side..":Out",input=side.."lp:In"})
    table.insert(links, {output=side.."lp:Out",input=side.."delay:In"})
  end
  local output = {}
  for i, channel in ipairs(positions) do
    local port = nil
    if channel == "FL" or channel == "FR" then port = channel..":Out"
    elseif channel == "SL" or channel == "RL" then port = "SLdelay:Out"
    elseif channel == "SR" or channel == "RR" then port = "SRdelay:Out" end
    if port then
      local name="out"..i
      table.insert(nodes, {type="builtin", name=name, label="copy"})
      table.insert(links, {output=port,input=name..":In"})
      output[i]=name..":Out"
    else
      local name="zero"..i
      table.insert(nodes, {type="builtin", name=name, label="mixer", control={["Gain 1"]=0}})
      table.insert(links, {output="L:Out",input=name..":In 1"})
      output[i]=name..":Out"
    end
  end
  return {nodes=nodes, links=links, inputs={"L:In","R:In"}, outputs=output}
end
local function output_positions (node)
  local value = node.properties["audio.position"]
  if value then
    local parsed=Json.Raw(value):parse()
    if type(parsed)=="table" and #parsed > 2 then return parsed end
  end
  for pod in node:iterate_params("EnumFormat") do
    local p=cutils.parseParam(pod,"EnumFormat")
    if p and type(p.position)=="table" and #p.position>2 then return p.position end
  end
  return nil
end
local function options (name)
  local raw = Json.Raw(Settings.get_string("sparky.audio.outputs"))
  if not raw or not raw:is_object() then return {} end
  local all = raw:parse()
  return all[name] or {}
end
local function is_headphone (node, source)
  local p = node.properties
  local dp = {}
  local device_id = tonumber(p["device.id"])
  if device_id then
    local dev = source:call("get-object-manager", "device"):lookup {
      Constraint { "bound-id", "=", device_id, type="gobject" }
    }
    if dev then
      dp = dev.properties
      for pod in dev:iterate_params("Route") do
        local route = cutils.parseParam(pod, "Route")
        if route and route.direction == "Output" and route.device == tonumber(p["card.profile.device"]) then
          for epod in dev:iterate_params("EnumRoute") do
            local e = cutils.parseParam(epod, "EnumRoute")
            if e and e.index == route.index and e.info and e.info["port.type"] then
              local kind=e.info["port.type"]
              if kind == "headphones" or kind == "headset" then return true end
              if kind == "speaker" or kind == "line" or kind == "hdmi" or kind == "spdif" then return false end
            end
          end
        end
      end
    end
  end
  local form = p["device.form-factor"] or p["device.form_factor"] or dp["device.form-factor"]
  local icon = p["device.icon-name"] or p["api.bluez5.icon"] or dp["device.icon-name"] or dp["api.bluez5.icon"]
  local profile = p["api.bluez5.profile"] or p["bluez5.profile"] or dp["api.bluez5.profile"] or dp["bluez5.profile"] or ""
  if form == "headphone" or form == "headphones" or form == "headset" or
    icon == "audio-headphones" or icon == "audio-headset" or profile:find("^headset%-head%-unit") ~= nil then return true end
  if form == "speaker" or form == "speakers" or icon == "audio-speakers" then return false end
  return nil
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
local function problem (output, profile, cause)
  local metadata = cutils.get_default_metadata_object()
  if metadata then
    local key = "sparky.audio.problem."..output
    if cause then
      metadata:set(0, key, "Spa:String:JSON", Json.Object { profile=profile, cause=cause }:to_string())
    else
      metadata:set(0, key, nil, nil)
    end
  end
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
  name="sparky-audio/physical-default",
  before="default-nodes/find-selected-default-node",
  interests={EventInterest {Constraint {"event.type","=","select-default-node"}}},
  execute=function(event)
    if event:get_properties()["default-node.type"] ~= "audio.sink" then return end
    local value=event:get_data("available-nodes")
    if not value then return end
    local available={}
    for _, props in ipairs(value:parse()) do
      if not (props["node.name"] or ""):find("^sparky%.audio%.") then
        table.insert(available,json(props))
      end
    end
    event:set_data("available-nodes",Json.Array(available))
  end,
}:register()
SimpleEventHook {
  name = "sparky-audio/encoded-output",
  before = {"linking/find-defined-target", "linking/find-default-target"},
  interests = { EventInterest { Constraint { "event.type", "=", "select-target" } } },
  execute = function (event)
    local source, om, si, props = lutils:unwrap_select_target_event(event)
    if props["media.class"] ~= "Stream/Output/Audio" or not cutils.parseBool(props["item.node.encoded-only"]) then return end
    local node=si:get_associated_proxy("node")
    if not node then return end
    local iec958=false
    for pod in node:iterate_params("EnumFormat") do
      local format=cutils.parseParam(pod,"EnumFormat")
      if format and format.mediaSubtype == "iec958" then iec958=true end
    end
    if not iec958 then return end
    local p=node.properties
    local metadata=cutils.get_default_metadata_object()
    local requested=nil
    local requested_id=nil
    if metadata and Settings.get_boolean("linking.allow-moving-streams") and not cutils.parseBool(p["node.dont-move"]) then
      requested=metadata:find(tonumber(props["node.id"]),"target.object")
      if not requested then requested_id=metadata:find(tonumber(props["node.id"]),"target.node") end
    end
    if not requested and not requested_id then
      requested=p["target.object"]
      if not requested then requested_id=p["node.target"] end
    end
    local intended=nil
    for candidate in om:iterate {type="SiLinkable"} do
      local cp=candidate.properties
      if cp["media.class"] == "Audio/Sink" then
        local cn=candidate:get_associated_proxy("node")
        if (requested and (cp["node.name"] == requested or (cn and cn.properties["object.serial"] == requested))) or
           (requested_id and tonumber(cp["node.id"]) == tonumber(requested_id)) then
          intended=candidate;break
        end
      end
    end
    if not requested and not requested_id then
      local id=cutils.getDefaultNode(props,"input")
      intended=om:lookup {type="SiLinkable",Constraint {"node.id","=",id}}
    end
    if intended and not lutils.canPassthrough(si,intended) then
      -- An unsupported format must fail negotiation on this output. Let the
      -- player retry PCM here instead of silently choosing another receiver.
      lutils.sendClientError(event,node,-95,"sparky.audio.codec-unavailable")
      node:request_destroy()
      event:stop_processing()
    end
  end,
}:register()
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
        if headphone == nil and count > 2 then
          problem(tp["node.name"],tp["node.name"],"output-type-unknown")
        elseif (headphone == false and count > 2) or opts.enabled == false then
          problem(tp["node.name"],"",nil)
        end
        local positions = output_positions(target_node)
        local matrix = not headphone and count == 2 and positions and (opts.matrix == "decode" or opts.matrix == "upmix")
        if (not matrix and (not headphone or count <= 2)) or opts.enabled == false or cutils.parseBool(props["item.node.encoded-only"]) then
          release(node.id); return
        end
        local layout = opts.layout or (count > 6 and "7.1" or "5.1")
        if not layouts[layout] then event:stop_processing(); problem(tp["node.name"], layout, "invalid-layout"); return end
        local filename = opts.hrtf or "/usr/share/libmysofa/MIT_KEMAR_normal_pinna.sofa"
        local kind = opts.kind or "sofa"
        local key = tp["node.name"]..":"..layout..":"..filename..":"..kind..":"..tostring(matrix and opts.matrix)..":"..tostring(opts.revision or 0)
        local old = filters[node.id]
        if old and old.key ~= key then release(node.id); old = nil end
        if not old then
          generation = generation + 1
          local name = "sparky.audio."..generation
          local args = {
            ["node.description"] = tp["node.description"] or tp["node.name"],
            ["filter.graph"] = graph(layout, filename, kind),
            ["capture.props"] = { ["node.name"]=name, ["media.class"]="Audio/Sink", ["node.virtual"]=true,
              ["sparky.audio.output"]=tp["node.name"], ["sparky.audio.profile"]=filename,
              ["sparky.audio.kind"]=matrix and "matrix" or kind,
              ["priority.session"]=-1000, ["audio.channels"]=#layouts[layout], ["audio.position"]=layouts[layout] },
            ["playback.props"] = { ["node.name"]=name..".output", ["node.passive"]=true,
              ["node.dont-fallback"]=true, ["node.linger"]=true, ["target.object"]=tp["node.name"],
              ["stream.dont-remix"]=true, ["audio.channels"]=2, ["audio.position"]={"FL", "FR"} },
          }
          local module = "libpipewire-module-filter-chain"
          if matrix then
            args["capture.props"]["audio.channels"]=2
            args["capture.props"]["audio.position"]={"FL","FR"}
            args["playback.props"]["audio.channels"]=#positions
            args["playback.props"]["audio.position"]=positions
            if opts.matrix == "decode" then
              args["filter.graph"]=matrix_graph(positions)
            else
              module="libpipewire-module-loopback"
              args["filter.graph"]=nil
              args["audio.position"]={"FL","FR"}
              args["playback.props"]["channelmix.upmix"]=true
              args["playback.props"]["channelmix.upmix-method"]="psd"
              args["playback.props"]["channelmix.lfe-cutoff"]=150
              args["playback.props"]["channelmix.fc-cutoff"]=12000
              args["playback.props"]["channelmix.rear-delay"]=12
            end
          end
          old = { name=name, key=key, module=LocalModule(module, json(args):to_string(), {}) }
          filters[node.id] = old
          if not old.module then release(node.id); event:stop_processing(); problem(tp["node.name"], filename, "hrtf-load-failed"); return end
        end
        local filter = om:lookup { type="SiLinkable", Constraint { "node.name", "=", old.name } }
        local output = om:lookup { type="SiLinkable", Constraint { "node.name", "=", old.name..".output" } }
        local link = output and lutils.lookupLink(output.id, target.id)
        local ready = link and (link:get_active_features() & Feature.SessionItem.ACTIVE) ~= 0
        if filter and ready then
          flags.can_passthrough = false
          event:set_data("target", filter)
          if not old.verified then problem(tp["node.name"], filename, nil); old.verified=true end
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
          problem(tp["node.name"], filename, "hrtf-load-timeout")
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

-- The standard hook's SiLink can fail before any public PipeWire Link is
-- exported. Own only IEC958 playback activation so that failure is reported.
-- Registration and flags follow linking/link-target.lua, Collabora, MIT.
SimpleEventHook {
  name="sparky-audio/encoded-link",
  after="linking/prepare-link",
  before="linking/link-target",
  interests={EventInterest {Constraint {"event.type","=","select-target"}}},
  execute=function(event)
    local source,om,si,p,flags,target=lutils:unwrap_select_target_event(event)
    if not target or p["media.class"] ~= "Stream/Output/Audio" or not flags.can_passthrough then return end
    local node=si:get_associated_proxy("node")
    local codec=nil
    for pod in node:iterate_params("EnumFormat") do
      local f=cutils.parseParam(pod,"EnumFormat")
      if f and f.mediaSubtype == "iec958" and type(f.iec958Codec) == "string" then codec=f.iec958Codec;break end
    end
    if not codec then return end
    local name=target.properties["node.name"]
    local function notice(cause)
      local metadata=cutils.get_default_metadata_object()
      if metadata then
        metadata:set(0,"sparky.audio.passthrough."..name..":"..codec,cause and "Spa:String:JSON" or nil,
          cause and Json.Object {output=name,codec=codec,cause=cause}:to_string() or nil)
      end
    end
    event:stop_processing()
    if flags.failed_peer_id == target.id and (flags.failed_count or 0) > 5 then return end
    local link=SessionItem("si-standard-link")
    if not link:configure {
      ["out.item"]=si,["in.item"]=target,["passthrough"]=true,
      ["exclusive"]=cutils.parseBool(p["node.exclusive"]),
      ["out.item.port.context"]="output",["in.item.port.context"]="input",
      ["main.item.id"]=si.id,["target.item.id"]=target.id,
    } then notice("link-configure-failed");return end
    link:connect("link-error",function(_,message)
      notice(message)
      lutils.sendClientError(event,node,-32,message)
    end)
    flags.was_handled=true;flags.peer_id=target.id;flags.failed_peer_id=target.id
    flags.failed_count=(flags.failed_count or 0)+1
    link:register()
    link:activate(Feature.SessionItem.ACTIVE,function(l,error)
      if error then
        notice(tostring(error));flags.peer_id=nil;l:remove()
      else
        notice(nil);flags.failed_peer_id=nil;flags.failed_count=0
      end
    end)
  end,
}:register()
