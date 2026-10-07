#!/usr/bin/env python3
"""A tiny local Invidious: just what PlasmaTube asks for to play one video. No network beyond 127.0.0.1.
usage: mock.py <port> <clips dir> <videos.json>
videos.json: {"<video id>": {"clip": "<file in clips dir>", "keywords": [...], "title": "..."}}
Piped shape is served too (/streams/<id>) so the keyword path can be tried on both."""
import json, os, re, sys, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

port, clips, vj = int(sys.argv[1]), sys.argv[2], sys.argv[3]
VIDEOS = json.load(open(vj))
LOG = open(os.environ.get('MOCK_LOG', '/dev/null'), 'a')

def video_json(vid, host):
    v = VIDEOS[vid]
    url = 'http://%s/clips/%s' % (host, v['clip'])
    base = {'title': v.get('title', vid), 'videoId': vid, 'author': 'Mock', 'authorId': 'UCmock', 'authorUrl': '/channel/UCmock',
            'lengthSeconds': 10, 'viewCount': 1, 'published': 1700000000, 'description': 'offline mock video', 'descriptionHtml': 'offline mock video',
            'keywords': v.get('keywords', []), 'likeCount': 1, 'dislikeCount': 0, 'isFamilyFriendly': True, 'allowedRegions': [], 'genre': 'Film',
            'genreUrl': '', 'authorThumbnails': [], 'subCountText': '1', 'allowRatings': True, 'rating': 5.0, 'isListed': True, 'liveNow': False,
            'recommendedVideos': [], 'videoThumbnails': [], 'adaptiveFormats': [],
            'formatStreams': [{'url': url, 'itag': '18', 'type': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"', 'format': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
                               'quality': 'medium', 'qualityLabel': '720p', 'resolution': '720p', 'container': 'mp4', 'fps': 25}]}
    if v.get('projection'):
        # an adaptive video format with the projection the way Invidious passes it on
        base['adaptiveFormats'] = [{'url': url, 'itag': '136', 'type': 'video/mp4; codecs="avc1.64001F"', 'encoding': 'h264', 'container': 'mp4',
                                    'resolution': '720p', 'qualityLabel': '720p', 'fps': 25, 'bitrate': '1000000', 'clen': '1000', 'projectionType': v['projection']}]
    return base

class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, fmt, *a): LOG.write('%s %s\n' % (self.command, self.path)); LOG.flush()
    def send_json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split('?')[0]
        host = self.headers.get('Host', '127.0.0.1:%d' % port)
        m = re.match(r'/api/v1/videos/([^/]+)$', p)
        if m and m.group(1) in VIDEOS: return self.send_json(video_json(m.group(1), host))
        if p.startswith('/api/v1/comments/'): return self.send_json({'commentCount': 0, 'videoId': '', 'comments': []})
        if p.startswith('/api/v1/trending') or p.startswith('/api/v1/popular'): return self.send_json([])
        m = re.match(r'/clips/([^/]+)$', p)
        if m and os.path.exists(os.path.join(clips, m.group(1))):
            time.sleep(float(os.environ.get('MOCK_DELAY', '1.5')))  # a network's latency: PlasmaTube's render context comes from its first frame
            f = os.path.join(clips, m.group(1)); size = os.path.getsize(f)
            rng = self.headers.get('Range'); start, end, code = 0, size - 1, 200
            if rng:
                mm = re.match(r'bytes=(\d*)-(\d*)', rng)
                if mm.group(1): start = int(mm.group(1))
                if mm.group(2): end = min(int(mm.group(2)), size - 1)
                code = 206
            self.send_response(code)
            self.send_header('Content-Type', 'video/x-matroska' if f.endswith('.mkv') else 'video/mp4'); self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            if code == 206: self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
            self.end_headers()
            with open(f, 'rb') as fh:
                fh.seek(start); left = end - start + 1
                try:
                    while left > 0:
                        d = fh.read(min(65536, left))
                        if not d: break
                        self.wfile.write(d); left -= len(d)
                except (BrokenPipeError, ConnectionResetError): pass
            return
        self.send_json({'error': 'not found'}, 404)

ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
