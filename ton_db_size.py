import asyncio, socket
import os

DB_PATH = "/var/ton-work/db"
UNIX_SOCKET_PATH = "/var/tmp/ton_db_size.sock"

def du(path):
    if os.path.islink(path):
        return (os.lstat(path).st_size, 0)
    if os.path.isfile(path):
        st = os.lstat(path)
        return (st.st_size, st.st_blocks * 512)
    total_bytes = 0
    have = []
    for dirpath, dirnames, filenames in os.walk(path):
        total_bytes += os.lstat(dirpath).st_blocks * 512
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if os.path.islink(fp):
                continue
            st = os.lstat(fp)
            if st.st_ino in have:
                continue  # skip hardlinks which were already counted
            have.append(st.st_ino)
            total_bytes += st.st_blocks * 512
        for d in dirnames:
            dp = os.path.join(dirpath, d)
            if os.path.islink(dp):
                apparent_total_bytes += os.lstat(dp).st_size
    return total_bytes


async def handle_client(reader, writer):
    response = str(int(du(DB_PATH) / 1024)).encode('utf8')
    writer.write(response)
    await writer.drain()
    writer.close()

async def run_server():
    server = await asyncio.start_unix_server(handle_client, path=UNIX_SOCKET_PATH)
    os.chmod(UNIX_SOCKET_PATH, 0o777)
    async with server:
        await server.serve_forever()

if os.path.exists(UNIX_SOCKET_PATH):
      os.remove(UNIX_SOCKET_PATH)

asyncio.run(run_server())
