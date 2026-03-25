from dataclasses import dataclass
from datetime import datetime
from http.client import HTTPException
from psycopg.errors import StringDataRightTruncation
from pydantic_core import to_jsonable_python
from typing import Optional
from uuid import UUID
import httpx
import main
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
