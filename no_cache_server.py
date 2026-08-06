import http.server
import socketserver

PORT = 5060

class NoCacheCORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Prevent any browser/proxy caching so users always get the latest
        # build (fixes stale Flutter Web PWA content after rebuilds).
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

with socketserver.TCPServer(('0.0.0.0', PORT), NoCacheCORSHandler) as httpd:
    httpd.serve_forever()
