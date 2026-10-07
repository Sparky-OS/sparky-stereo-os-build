// usage: node pt-transcode.mjs <peertube root> <input> <output> [resolution]
// What PeerTube's server does for a web video file (server/core/lib/transcoding/web-transcoding.ts): quick transcode when
// canDoQuickVideoTranscode and the audio allow it, else a full transcode, with the default x264 profile, through FFmpegVOD
import { createRequire } from 'module'
const [ root, input, output, resolutionArg ] = process.argv.slice(2)
const ff = await import(root + '/packages/ffmpeg/' + (process.env.FFDIST || 'dist') + '/index.js')
const { Mutex } = await import('async-mutex')
const mutex = new Mutex()
const probe = await ff.ffprobePromise(input)
const quick = await ff.canDoQuickVideoTranscode(input, 60, probe) && await ff.canDoQuickAudioTranscode(input, probe)
const dims = await ff.getVideoStreamDimensionsInfo(input, probe)
const fps = await ff.getVideoStreamFPS(input, probe)
const type = quick && !process.env.FORCE_VIDEO ? 'quick-transcode' : 'video'
console.log(JSON.stringify({ input, type, stereo3D: await ff.getVideoStreamStereo3D?.(input, probe) ?? 'n/a', resolution: dims.resolution }))
const logger = { info: () => {}, debug: () => {}, warn: console.warn, error: console.error }
const vod = new ff.FFmpegVOD({
  availableEncoders: { available: ff.getDefaultAvailableEncoders(), encodersToTry: ff.getDefaultEncodersToTry() }, profile: 'default', niceness: 0, tmpDirectory: '/tmp', threads: 2, logger
})
await vod.transcode({ type, videoInputPath: input, outputPath: output, inputFileMutexReleaser: await mutex.acquire(), resolution: Number(resolutionArg || dims.resolution), fps })
console.log('done', output)
