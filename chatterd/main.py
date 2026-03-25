import handlers
from contextlib import asynccontextmanager
from psycopg_pool import AsyncConnectionPool
from starlette.applications import Starlette
from starlette.routing import Route

@asynccontextmanager
async def lifespan(server):
    server.pool = AsyncConnectionPool("dbname=chatterdb user=chatter password=chattchatt host=localhost", open=False)
    await server.pool.open()
    yield
    await server.pool.close()

routes = [
    Route('/', handlers.top, methods=['GET']),
    Route('/llmprompt', handlers.llmprompt, methods=['POST']),
    Route('/getchatts', handlers.getchatts, methods=['GET']),
    Route('/postchatt', handlers.postchatt, methods=['POST']),
]

# must come after routes and lifespan definitions
server = Starlette(routes=routes, lifespan=lifespan)
