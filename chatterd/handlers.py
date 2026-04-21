from dataclasses import dataclass, field
from dataclasses_json import dataclass_json, config
from datetime import datetime
from http import HTTPStatus
from psycopg.errors import StringDataRightTruncation
from pydantic_core import to_jsonable_python
from typing import List, Optional
import httpx
import json
import main
import re
import toolbox
from toolbox import TOOLBOX, OllamaToolCall, OllamaToolSchema, getWeather, toolInvoke
from sse_starlette.sse import EventSourceResponse
from starlette.background import BackgroundTask
from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse, Response, StreamingResponse
from google.auth.transport import requests
from google.oauth2 import id_token
import hashlib, time

async def top(request):
    return JSONResponse('EECS Reactive chatterd', status_code=200)

OLLAMA_BASE_URL = "http://localhost:11434/api"
asyncClient = httpx.AsyncClient(timeout=None, http2=True)

async def llmprompt(request):
    response = await asyncClient.send(
        asyncClient.build_request(
            method=request.method,
            url=f"{OLLAMA_BASE_URL}/generate",
            data=await request.body()
        ), stream=True)
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
                await cursor.execute('INSERT INTO chatts (name, message, id) VALUES (%s, %s, gen_random_uuid());', (chatt.name, chatt.message))
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
    toolCalls: list[toolbox.OllamaToolCall] | None = field(
        default=None,
        metadata=config(field_name="tool_calls", exclude=lambda l: not l)
    )

    @staticmethod
    def fromRow(row, ollamaRequest):
        try:
            toolcalls = []
            if row[2]:
                toolcalls = [OllamaToolCall.from_dict(tc) for tc in json.loads(row[2])]
            ollamaRequest.messages.append(OllamaMessage(role=row[0], content=row[1], toolCalls=toolcalls))
            if row[3]:
                ollamaRequest.tools.extend([OllamaToolSchema.from_dict(t) for t in json.loads(row[3])])
        except Exception as err:
            raise err

@dataclass_json
@dataclass
class OllamaRequest:
    appID: str
    model: str
    messages: List[OllamaMessage]
    stream: bool
    tools: list[toolbox.OllamaToolSchema] | None = field(
        default=None,
        metadata=config(exclude=lambda l: not l)
    )

@dataclass_json
@dataclass
class OllamaResponse:
    model: str
    message: OllamaMessage

@dataclass
class Location:
    lat: str
    lon: str

@dataclass
class AuthChatt:
    chatterID: str
    message: str

@dataclass
class Chatter:
    clientID: str
    idToken: str

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
                return JSONResponse({"error": f'Inserting tools: {type(err).__name__}: {str(err)}'}, status_code=HTTPStatus.INTERNAL_SERVER_ERROR)
            ollamaRequest.messages = []
            try:
                await cur.execute("SELECT name, message FROM chatts WHERE appid = %s ORDER BY time ASC;", (ollamaRequest.appID,))
                rows = await cur.fetchall()
                ollamaRequest.messages = [OllamaMessage(role=row[0], content=row[1], toolCalls=None) for row in rows]
            except Exception as err:
                return JSONResponse({"error": f'{type(err).__name__}: {str(err)}'}, status_code=HTTPStatus.INTERNAL_SERVER_ERROR)

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
                                yield {"event": "error", "data": f'{{"error": {json.dumps(str(err))}}}'}
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
                                        yield {"event": "latlon", "data": f'{{"lat": {lat}, "lon": {lon}}}'}
                                    except Exception:
                                        pass
                except Exception as err:
                    yield {"event": "error", "data": f'{{"error": {json.dumps(str(err))}}}'}
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
                return JSONResponse({"error": f'{type(err).__name__}: {str(err)}'}, status_code=HTTPStatus.INTERNAL_SERVER_ERROR)
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
                await cursor.execute('INSERT INTO chatts (name, message, id, geodata) VALUES (%s, %s, gen_random_uuid(), %s);', (chatt.name, chatt.message, chatt.geodata))
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

async def weather(request):
    try:
        loc = Location(**(await request.json()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'Unprocessable entity: {str(err)}', status_code=HTTPStatus.UNPROCESSABLE_ENTITY)
    temp, err = await getWeather([loc.lat, loc.lon])
    return JSONResponse({"error": f'Internal server error: {str(err)}'}, status_code=HTTPStatus.INTERNAL_SERVER_ERROR) if err else JSONResponse(temp)

async def llmtools(request):
    try:
        ollamaRequest = OllamaRequest.from_json(await request.body(), infer_missing=True)
    except Exception as err:
        return JSONResponse({"error": f"Deserializing request: {type(err).__name__}: {str(err)}"}, status_code=HTTPStatus.UNPROCESSABLE_ENTITY)

    client_tools = ""
    if ollamaRequest.tools:
        try:
            client_tools = json.dumps([tool.to_dict() for tool in ollamaRequest.tools])
        except Exception as err:
            return JSONResponse({"error": f"Serializing request tools: {type(err).__name__}: {str(err)}"}, status_code=HTTPStatus.UNPROCESSABLE_ENTITY)

    async def ndjson_yield_sse():
        nonlocal client_tools
        sendNewPrompt = True
        async with main.server.pool.connection() as conn:
            async with conn.cursor() as cur:
                while sendNewPrompt:
                    sendNewPrompt = False
                    try:
                        first_msg = True
                        for msg in ollamaRequest.messages:
                            tools_to_store = client_tools if first_msg else None
                            await cur.execute(
                                "INSERT INTO chatts (name, message, id, appid, toolschemas) VALUES (%s, %s, gen_random_uuid(), %s, %s);",
                                (msg.role, msg.content, ollamaRequest.appID, tools_to_store),
                            )
                            first_msg = False
                        client_tools = ""

                        ollamaRequest.tools = [tool.schema for tool in TOOLBOX.values()]

                        await cur.execute(
                            "SELECT name, message, toolcalls, toolschemas FROM chatts WHERE appID = %s ORDER BY time ASC;",
                            (ollamaRequest.appID,),
                        )
                        rows = await cur.fetchall()
                        ollamaRequest.messages = []
                        for row in rows:
                            OllamaMessage.fromRow(row, ollamaRequest)

                        async with asyncClient.stream(
                            method="POST",
                            url=f"{OLLAMA_BASE_URL}/chat",
                            content=ollamaRequest.to_json().encode("utf-8"),
                        ) as response:
                            tokens = []
                            async for line in response.aiter_lines():
                                if not line:
                                    continue
                                try:
                                    ollamaResponse = OllamaResponse.from_json(line)
                                except Exception:
                                    yield {"data": line}
                                    continue
                                if ollamaResponse.message.content:
                                    tokens.append(ollamaResponse.message.content)
                                if ollamaResponse.message.toolCalls:
                                    tool_calls_json = json.dumps([tc.to_dict() for tc in ollamaResponse.message.toolCalls])
                                    for toolCall in ollamaResponse.message.toolCalls:
                                        if not toolCall.function.name:
                                            continue
                                        await cur.execute(
                                            "INSERT INTO chatts (name, message, id, appID, toolcalls) VALUES (%s, %s, gen_random_uuid(), %s, %s);",
                                            ("assistant", "".join(tokens), ollamaRequest.appID, tool_calls_json),
                                        )
                                        tokens.clear()
                                        tool_calls_json = ""
                                        tool_result, tool_err = await toolInvoke(toolCall.function)
                                        if tool_err:
                                            tool_result = tool_err
                                        if tool_result:
                                            ollamaRequest.messages.append(ollamaResponse.message)
                                            ollamaRequest.messages.append(OllamaMessage(role="tool", content=tool_result, toolCalls=None))
                                            ollamaRequest.tools = None
                                            sendNewPrompt = True
                                            await cur.execute(
                                                "INSERT INTO chatts (name, message, id, appID) VALUES (%s, %s, gen_random_uuid(), %s);",
                                                ("tool", re.sub(r"\s+", " ", tool_result), ollamaRequest.appID),
                                            )
                                        else:
                                            yield {"event": "tool_calls", "data": line}
                                else:
                                    yield {"data": line}
                            if tokens:
                                await cur.execute(
                                    "INSERT INTO chatts (name, message, id, appID) VALUES (%s, %s, gen_random_uuid(), %s);",
                                    ("assistant", "".join(tokens), ollamaRequest.appID),
                                )
                    except Exception as err:
                        print(f"llmtools error: {err=}")
                        yield {"data": json.dumps({"error": str(err)})}

    return EventSourceResponse(ndjson_yield_sse())

async def adduser(request):
    try:
        chatter = Chatter(**(await request.json()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse('Unprocessable entity', status_code=422)
    now = time.time()  # secs since epoch (1/1/70, 00:00:00 UTC)
    try:
        idinfo = id_token.verify_oauth2_token(chatter.idToken, requests.Request(), chatter.clientID, clock_skew_in_seconds=50)
    except ValueError as err:
        return JSONResponse('Unauthroized', status_code=401)
    try:
        username = idinfo['name']
    except:
        username = "Profile NA"
    # Compute chatterID
    backendSecret = "ifyougiveamouse"  # or server's private key
    nonce = str(now)
    hashable = chatter.idToken + backendSecret + nonce
    chatterID = hashlib.sha256(hashable.strip().encode('utf-8')).hexdigest()
    lifetime = min(int(idinfo['exp']-now)+1, 300)  # secs, up to 1800, idToken lifetime
    # add to database
    try:
        async with main.server.pool.connection() as connection:
            async with connection.cursor() as cursor:
                await cursor.execute('DELETE FROM chatters WHERE %s > expiration;', (now, ))
                await cursor.execute('INSERT INTO chatters (chatterid, username, expiration) VALUES '
                                     '(%s, %s, %s);', (chatterID, username, now+lifetime))
                return JSONResponse({'username': username, 'chatterID': chatterID, 'lifetime': lifetime})
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'{type(err).__name__}: {str(err)}', status_code=500)

async def postauth(request):
    try:
        chatt = AuthChatt(**(await request.json()))
    except Exception as err:
        print(f'{err=}')
        return JSONResponse('Unprocessable entity', status_code=422)
    try:
        async with main.server.pool.connection() as connection:
            async with connection.cursor() as cursor:
                await cursor.execute('SELECT username, expiration FROM chatters WHERE chatterID = %s;',
                                     (chatt.chatterID,))
                row = await cursor.fetchone()
                now = time.time()
                if row is None or now > row[1]:
                    return JSONResponse('Unauthorized', status_code=401)
                # insert chatt
                await cursor.execute('INSERT INTO chatts (name, message, id) VALUES (%s, %s, gen_random_uuid());',
                                     (row[0], chatt.message))
                return JSONResponse({})
    except Exception as err:
        print(f'{err=}')
        return JSONResponse(f'{type(err).__name__}: {str(err)}', status_code=500)
