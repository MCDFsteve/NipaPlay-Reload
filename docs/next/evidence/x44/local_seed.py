"""Temporary loopback BT seed. All three videos are experimenter-created CC0.
The gate makes first-file completion observable before the rest; it is lab input,
not application scheduling. Nothing contacts a public tracker or shares user files.
"""
import hashlib, socket, socketserver, struct, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def encode(value):
    if isinstance(value, int): return b'i'+str(value).encode()+b'e'
    if isinstance(value, str): value=value.encode()
    if isinstance(value, bytes): return str(len(value)).encode()+b':'+value
    if isinstance(value, list): return b'l'+b''.join(encode(x) for x in value)+b'e'
    return b'd'+b''.join(encode(k)+encode(v) for k,v in sorted(value.items()))+b'e'

def seed(videos, torrent, title, gates, trace, peer_port=0, tracker_port=0, initial_partial=False):
    content=b''.join(v.read_bytes() for v in videos); size=16384
    ends=[]; total=0
    for video in videos:
        total+=video.stat().st_size; ends.append((total+size-1)//size)
    def available(index):
        if initial_partial and index < ends[0]-1: return True
        return gates[next(i for i,end in enumerate(ends) if index<end)].is_set()
    info={b'name':title.encode(), b'files':[{b'length':v.stat().st_size,
          b'path':[f'第{i+1:02d}集.mp4'.encode()]} for i,v in enumerate(videos)],
          b'piece length':size, b'pieces':b''.join(hashlib.sha1(content[i:i+size]).digest()
          for i in range(0,len(content),size)), b'private':1}
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
            s=self.request; s.settimeout(180)
            queue=[]; condition=threading.Condition(); stopped=threading.Event()
            connected=time.monotonic()
            def respond():
                while not stopped.is_set():
                    with condition:
                        eligible=[q for q in queue if available(q[0])]
                        if not eligible:
                            condition.wait(.1); continue
                        req=min(eligible); queue.remove(req)
                    index,offset,n=req
                    block=content[index*size+offset:index*size+offset+n]
                    try: s.sendall(struct.pack('>I',len(block)+9)+b'\x07'+struct.pack('>II',index,offset)+block)
                    except OSError: break
                    trace.append({'at':time.time(),'piece':index,'offset':offset,'bytes':len(block)})
                    time.sleep(.03)
            try:
                header=recv(s,68); assert header[28:48]==info_hash
                s.sendall(b'\x13BitTorrent protocol'+bytes(8)+info_hash+b'-X44CC0-000000000000')
                count=(len(content)+size-1)//size
                bits=bytearray((count+7)//8)
                sent=set()
                for i in range(count):
                    if available(i): bits[i//8] |= 1 << (7-i%8); sent.add(i)
                s.sendall(struct.pack('>I',len(bits)+1)+b'\x05'+bits+struct.pack('>I',1)+b'\x01')
                def announce():
                    while not stopped.is_set():
                        for i in range(count):
                            if available(i) and i not in sent:
                                try: s.sendall(struct.pack('>I',5)+b'\x04'+struct.pack('>I',i))
                                except OSError: return
                                sent.add(i)
                        stopped.wait(.1)
                threading.Thread(target=announce,daemon=True).start()
                threading.Thread(target=respond,daemon=True).start()
                while True:
                    length=struct.unpack('>I',recv(s,4))[0]
                    if not length: continue
                    msg=recv(s,length)
                    if msg[0]==6:
                        with condition:
                            queue.append(struct.unpack('>III',msg[1:])); condition.notify()
            except (EOFError,OSError,AssertionError): pass
            finally: stopped.set()
    class Server(socketserver.ThreadingTCPServer): allow_reuse_address=True
    peer=Server(('127.0.0.1',peer_port),Peer); peer.daemon_threads=True
    class Tracker(BaseHTTPRequestHandler):
        def do_GET(self):
            body=encode({b'interval':1,b'complete':1,b'incomplete':0,
                b'peers':socket.inet_aton('127.0.0.1')+struct.pack('>H',peer.server_address[1])})
            self.send_response(200); self.end_headers(); self.wfile.write(body)
        def log_message(self,*args): pass
    tracker=ThreadingHTTPServer(('127.0.0.1',tracker_port),Tracker)
    torrent.write_bytes(encode({b'announce':f'http://127.0.0.1:{tracker.server_address[1]}/announce',
        b'info':info,b'comment':b'Experimenter-created three animated test patterns. CC0-1.0 dedication. Distribution permitted.'}))
    for server in (peer,tracker): threading.Thread(target=server.serve_forever,daemon=True).start()
    return peer,tracker
