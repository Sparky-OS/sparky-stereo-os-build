local mp = require 'mp'
local utils = require 'mp.utils'
local captured = false
mp.register_event('playback-restart', function()
    if captured then return end
    captured = true
    mp.add_timeout(1.5, function()
        local output = os.getenv('CAPTURE_OUTPUT')
        mp.commandv('screenshot-to-file', output .. '.png', 'video')
        local f = assert(io.open(output .. '.json', 'w'))
        f:write(utils.format_json({
            source = mp.get_property_native('video-params'),
            output = mp.get_property_native('video-out-params'),
            decoder = mp.get_property('hwdec-current'),
            interop = mp.get_property('hwdec-interop')
        }))
        f:close()
        mp.commandv('quit')
    end)
end)
