from dataclasses import dataclass
from dataclasses_json import dataclass_json
from datetime import datetime
from http import HTTPStatus
from http.client import HTTPException
from psycopg.errors import StringDataRightTruncation
from pydantic_core import to_jsonable_python
from typing import List, Optional
from uuid import UUID
import httpx
import json
import main
import re
from sse_starlette.sse import EventSourceResponse
from starlette.background import BackgroundTask
from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse, Response, StreamingResponse

async def top(request):
    return JSONResponse('EECS Reactive chatterd', status_code=200)

OLLAMA_BASE_URL = "http://localhost:11434/api"
asyncClient = httpx.AsyncClient(timeout=None, http2=True)

async def llmprompt(request):
    response = await asyncClient.send(
        asyncClient.build_request(
            method = request.method,
            url = f"{OLLAMA_BASE_URL}/generate",
            data=await request.body()
        ), stream = True)
    if response.status_code != 200:
        return Response(headers=response.headers, content=await response.aread())
    return StreamingResponse(response.aiter_raw(),
        media_type="application/x-ndjson",
        background=BackgroundTask(response.aclose))

@dataclass
class Chatt:
    name: str
    message: str
    geodata: Optional[str] = None

async def getchatts(request):
    try:
        async with main.server.pool.connection() as connection:
            async with connection.cursor() as cursor:
                await cursor.execute('SELECT name, message, id, time FROM chatts ORDER BY time ASC;')
                return JSONResponse(to_jsonable_python(await cursor.fetchall()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'{type(err).__name__}: {str(err)}', status_code=500)

async def postchatt(request):
    try:
        chatt = Chatt(**(await request.json()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'Unprocessable entity: {str(err)}', status_code=422)
    try:
        async with main.server.pool.connection() as connection:
            async with connection.cursor() as cursor:
                await cursor.execute('INSERT INTO chatts (name, message, id) VALUES '
                    '(%s, %s, gen_random_uuid());', (chatt.name, chatt.message))
                return JSONResponse({})
    except StringDataRightTruncation as err:
        print(f'Message too long: {str(err)}')
        return JSONResponse(f'Message too long: {str(err)}', status_code=400)
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'{type(err).__name__}: {str(err)}', status_code=500)

@dataclass_json
@dataclass
class OllamaMessage:
    role: str
    content: str

@dataclass_json
@dataclass
class OllamaRequest:
    appID: str
    model: str
    messages: List[OllamaMessage]
    stream: bool

@dataclass_json
@dataclass
class OllamaResponse:
    model: str
    message: OllamaMessage

async def llmchat(request):
    try:
        ollamaRequest = OllamaRequest.from_json(await request.body(), infer_missing=True)
    except Exception as err:
        return JSONResponse({"error": f'Deserializing request: {type(err).__name__}: {str(err)}'}, status_code=HTTPStatus.UNPROCESSABLE_ENTITY)
    async with main.server.pool.connection() as conn:
        async with conn.cursor() as cur:
            try:
                for msg in ollamaRequest.messages:
                    await cur.execute(
                        'INSERT INTO chatts (name, message, id, appid) VALUES (%s, %s, gen_random_uuid(), %s);',
                        (msg.role, msg.content, ollamaRequest.appID,)
                    )
            except Exception as err:
                return JSONResponse({"error": f'Inserting tools: {type(err).__name__}: {str(err)}'},
                    status_code=HTTPStatus.INTERNAL_SERVER_ERROR)
            ollamaRequest.messages = []
            try:
                await cur.execute("SELECT name, message FROM chatts WHERE appid = %s ORDER BY time ASC;",
                    (ollamaRequest.appID,))
                rows = await cur.fetchall()
                ollamaRequest.messages = [OllamaMessage(role=row[0], content=row[1]) for row in rows]
            except Exception as err:
                return JSONResponse({"error": f'{type(err).__name__}: {str(err)}'},
                    status_code=HTTPStatus.INTERNAL_SERVER_ERROR)

    async def ndjson_yield_sse():
        async with main.server.pool.connection() as conn:
            async with conn.cursor() as cur:
                try:
                    async with asyncClient.stream(
                        method=request.method,
                        url=f"{OLLAMA_BASE_URL}/chat",
                        content=ollamaRequest.to_json().encode("utf-8"),
                    ) as response:
                        tokens = []
                        async for line in response.aiter_lines():
                            try:
                                ollamaResponse = OllamaResponse.from_json(line)
                                tokens.append(re.sub(r"\s+", " ", ollamaResponse.message.content))
                                yield {"data": line}
                            except Exception as err:
                                yield {
                                    "event": "error",
                                    "data": f'{{"error": {json.dumps(str(err))}}}'
                                }
                        if tokens:
                            completion = "".join(tokens)
                            await cur.execute(
                                'INSERT INTO chatts (name, message, id, appid) VALUES (%s, %s, gen_random_uuid(), %s);',
                                ("assistant", completion, ollamaRequest.appID,)
                            )
                            if "WINNER!!!" in completion:
                                parts = completion.split(":")
                                if len(parts) >= 3:
                                    try:
                                        lat = float(parts[1])
                                        lon = float(parts[2])
                                        yield {
                                            "event": "latlon",
                                            "data": f'{{"lat": {lat}, "lon": {lon}}}'
                                        }
                                    except Exception:
                                        pass
                except Exception as err:
                    yield {
                        "event": "error",
                        "data": f'{{"error": {json.dumps(str(err))}}}'
                    }
    return EventSourceResponse(ndjson_yield_sse())

async def llmprep(request):
    try:
        ollamaRequest = OllamaRequest.from_json(await request.body(), infer_missing=True)
    except Exception as err:
        return JSONResponse({"error": f'Deserializing request: {type(err).__name__}: {str(err)}'}, status_code=HTTPStatus.UNPROCESSABLE_ENTITY)
    async with main.server.pool.connection() as conn:
        async with conn.cursor() as cur:
            try:
                await cur.execute("DELETE FROM chatts WHERE appID = %s;", (ollamaRequest.appID,))
                for msg in ollamaRequest.messages:
                    await cur.execute(
                        'INSERT INTO chatts (name, message, id, appid) VALUES (%s, %s, gen_random_uuid(), %s);',
                        (msg.role, msg.content, ollamaRequest.appID,)
                    )
            except Exception as err:
                return JSONResponse({"error": f'{type(err).__name__}: {str(err)}'},
                    status_code=HTTPStatus.INTERNAL_SERVER_ERROR)
    print(f'llmprep: {ollamaRequest.appID}')
    return JSONResponse({})
async def postmaps(request):
    try:
        chatt = Chatt(**(await request.json()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'Unprocessable entity: {str(err)}', status_code=422)
    try:
        async with main.server.pool.connection() as connection:
            async with connection.cursor() as cursor:
                await cursor.execute('INSERT INTO chatts (name, message, id, geodata) VALUES '
                    '(%s, %s, gen_random_uuid(), %s);', (chatt.name, chatt.message, chatt.geodata))
                return JSONResponse({})
    except StringDataRightTruncation as err:
        print(f'Message too long: {str(err)}')
        return JSONResponse(f'Message too long: {str(err)}', status_code=400)
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'{type(err).__name__}: {str(err)}', status_code=500)

async def getmaps(request):
    try:
        async with main.server.pool.connection() as connection:
            async with connection.cursor() as cursor:
                await cursor.execute('SELECT name, message, id, time, geodata FROM chatts ORDER BY time ASC;')
                return JSONResponse(to_jsonable_python(await cursor.fetchall()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'{type(err).__name__}: {str(err)}', status_code=500)
