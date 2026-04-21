from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from dataclasses_json import dataclass_json, config
from http import HTTPStatus
import httpx
import pkgutil

@dataclass_json
@dataclass
class OllamaParamProp:
    type: str
    description: str
    enum: list[str] | None = None

@dataclass_json
@dataclass
class OllamaFunctionParams:
    type: str
    properties: dict[str, OllamaParamProp]
    required: list[str] | None = None

@dataclass_json
@dataclass
class OllamaToolFunction:
    name: str
    description: str
    parameters: OllamaFunctionParams | None = None

@dataclass_json
@dataclass
class OllamaToolSchema:
    type: str
    function: OllamaToolFunction

WEATHER_JSON = pkgutil.get_data(__name__, "tools/get_weather.json").decode("utf-8")

@dataclass_json
@dataclass
class Current:
    temp: float = field(
        default=0.0,
        metadata=config(field_name="temperature_2m")
    )

@dataclass_json
@dataclass
class OMeteoResponse:
    latitude: float
    longitude: float
    current: Current

async def getWeather(argv: list[str]) -> tuple[str | None, str | None]:
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                url=f"https://api.open-meteo.com/v1/forecast?latitude={argv[0]}&longitude={argv[1]}&current=temperature_2m&temperature_unit=fahrenheit"
            )
        if response.status_code != HTTPStatus.OK:
            return None, f"Open-meteo response: {response.status_code}"
        ometeoResponse = OMeteoResponse.from_json(response.content)
        return f"Weather at lat: {ometeoResponse.latitude}, lon: {ometeoResponse.longitude} is {ometeoResponse.current.temp}F", None
    except Exception as err:
        return None, f"Cannot connect to Open Meteo: {err}"

type ToolFunction = Callable[[list[str]], Awaitable[tuple[str | None, str | None]]]

@dataclass
class Tool:
    schema: OllamaToolSchema
    function: ToolFunction

TOOLBOX: dict[str, Tool] = {
    "get_weather": Tool(OllamaToolSchema.from_json(WEATHER_JSON), getWeather),
}

@dataclass_json
@dataclass
class OllamaFunctionCall:
    name: str
    arguments: dict[str, str]

@dataclass_json
@dataclass
class OllamaToolCall:
    function: OllamaFunctionCall

async def toolInvoke(function: OllamaFunctionCall) -> tuple[str | None, str | None]:
    tool = TOOLBOX.get(function.name)
    if tool:
        argv = [function.arguments[prop] for prop in tool.schema.function.parameters.required]
        return await tool.function(argv)
    return None, None
