"""Loopback-only BT seed for a video created by the experimenter and dedicated CC0.

No downloaded third-party media, dependencies, remote trackers or stored secrets.
"""
import hashlib, socket, socketserver, struct, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def encode(value):
    if isinstance(value, int): return b'i'+str(value).encode()+b'e'
    if isinstance(value, str): value=value.encode()
    if isinstance(value, bytes): return str(len(value)).encode()+b':'+value
    if isinstance(value, list): return b'l'+b''.join(encode(x) for x in value)+b'e'
    return b'd'+b''.join(encode(k)+encode(v) for k,v in sorted(value.items()))+b'e'

def seed(video, torrent, name='delivered-cc0.mp4'):
    content=video.read_bytes(); size=16384
    info={b'name':name.encode(), b'length':len(content), b'piece length':size,
          b'pieces':b''.join(hashlib.sha1(content[i:i+size]).digest() for i in range(0,len(content),size)), b'private':1}
    info_hash=hashlib.sha1(encode(info)).digest()
    def recv(sock,n):
        result=b''
        while len(result)<n:
            block=sock.recv(n-len(result))
            if not block: raise EOFError()
            result+=block
        return result
    class Peer(socketserver.BaseRequestHandler):
        def handle(self):
            s=self.request; s.settimeout(120)
            try:
                header=recv(s,68)
                assert header[28:48]==info_hash
                s.sendall(b'\x13BitTorrent protocol'+bytes(8)+info_hash+b'-X35CC0-000000000000')
                count=(len(content)+size-1)//size
                bits=bytes([255])*((count+7)//8)
                s.sendall(struct.pack('>I',len(bits)+1)+b'\x05'+bits+struct.pack('>I',1)+b'\x01')
                while True:
                    length=struct.unpack('>I',recv(s,4))[0]
                    if not length: continue
                    msg=recv(s,length)
                    if msg[0]==6:
                        index,offset,n=struct.unpack('>III',msg[1:])
                        block=content[index*size+offset:index*size+offset+n]
                        s.sendall(struct.pack('>I',len(block)+9)+b'\x07'+struct.pack('>II',index,offset)+block)
            except (EOFError,OSError,AssertionError): pass
    peer=socketserver.ThreadingTCPServer(('127.0.0.1',0),Peer); peer.daemon_threads=True
    class Tracker(BaseHTTPRequestHandler):
        def do_GET(self):
            body=encode({b'interval':1,b'complete':1,b'incomplete':0,b'peers':socket.inet_aton('127.0.0.1')+struct.pack('>H',peer.server_address[1])})
            self.send_response(200); self.end_headers(); self.wfile.write(body)
        def log_message(self,*args): pass
    tracker=ThreadingHTTPServer(('127.0.0.1',0),Tracker)
    torrent.write_bytes(encode({b'announce':f'http://127.0.0.1:{tracker.server_address[1]}/announce',b'info':info,b'comment':b'Experimenter-created color video, CC0 dedication; temporary local seed'}))
    for server in (peer,tracker): threading.Thread(target=server.serve_forever,daemon=True).start()
    return peer,tracker
