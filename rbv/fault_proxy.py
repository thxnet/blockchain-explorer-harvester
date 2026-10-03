import asyncio
import json
import os

import websockets

UPSTREAM = os.environ["UPSTREAM_WS"]
LISTEN_PORT = int(os.environ["LISTEN_PORT"])
FAIL_EVERY = int(os.environ["FAIL_EVERY"])
ERROR = {"code": -32050, "message": "Upstream response unavailable"}


async def handle(client):
    count = 0
    async with websockets.connect(UPSTREAM, max_size=None, ping_interval=None) as upstream:
        async def down():
            async for message in upstream:
                await client.send(message)

        downstream = asyncio.create_task(down())
        try:
            async for message in client:
                count += 1
                request = json.loads(message)
                if count % FAIL_EVERY == 0:
                    print(f"inject method={request.get('method')} id={request.get('id')} n={count}", flush=True)
                    await client.send(json.dumps({"jsonrpc": "2.0", "id": request.get("id"), "error": ERROR}))
                    continue
                await upstream.send(message)
        finally:
            downstream.cancel()


async def main():
    async with websockets.serve(handle, "0.0.0.0", LISTEN_PORT, max_size=None, ping_interval=None):
        print(f"fault proxy :{LISTEN_PORT} -> {UPSTREAM} fail_every={FAIL_EVERY}", flush=True)
        await asyncio.Future()


asyncio.run(main())
