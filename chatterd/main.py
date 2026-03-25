import handlers
from starlette.applications import Starlette
from starlette.routing import Route

routes = [
    Route('/', handlers.top, methods=['GET']),
    Route('/llmprompt', handlers.llmprompt, methods=['POST']),
]

# must come after route definitions
server = Starlette(routes=routes)
