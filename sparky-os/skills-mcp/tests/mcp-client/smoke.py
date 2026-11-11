"""A real MCP client (the official Python SDK) drives `sparky-stereo-skills serve` over stdio and prints what it saw.
Usage: smoke.py MODE   where MODE is legacy, auto or the stateless version string. Prints KEY=value lines for the shell
harness (run-smoke.sh) to check; any exception ends in a nonzero exit with the traceback on stderr."""
import asyncio
import json
import os
import sys

from mcp import Client
from mcp.client.stdio import StdioServerParameters

mode = sys.argv[1]
engine = os.environ.get("ENGINE", "/usr/bin/sparky-stereo-skills")
env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "XDG_DATA_DIRS", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "SPARKY_STEREO_PACKAGES", "SPARKY_STEREO_REF", "LANG")}


def text(result):
    return "".join(c.text for c in result.content if getattr(c, "type", "") == "text")


async def main():
    params = StdioServerParameters(command=engine, args=["serve"], env=env)
    async with Client(params, mode=mode) as c:
        print("PROTOCOL=" + str(c.protocol_version))
        info = c.server_info
        print("SERVER=" + (f"{info.name} {info.version}" if info else "none"))
        print("INSTRUCTIONS=" + str(c.instructions)[:60].replace("\n", " "))
        caps = c.server_capabilities
        print("CAP_TOOLS=" + str(caps.tools is not None) + " CAP_RESOURCES=" + str(caps.resources is not None))
        print("CAP_EXT=" + json.dumps(sorted((caps.extensions or {}).keys())))
        tools = await c.list_tools()
        names = sorted(t.name for t in tools.tools)
        print("TOOLS=" + ",".join(names))
        schema_ok = all(t.input_schema.get("type") == "object" for t in tools.tools)
        print("SCHEMAS_OBJECT=" + str(schema_ok))
        ro = {t.name: bool(t.annotations and t.annotations.read_only_hint) for t in tools.tools}
        print("READONLY=" + ",".join(f"{k}:{v}" for k, v in sorted(ro.items())))
        r = await c.call_tool("skills_find", {"query": "widgets broken", "limit": 2})
        print("FIND_ERROR=" + str(r.is_error))
        print("FIND_FIRST=" + text(r).splitlines()[1].split(" ")[1])
        r = await c.call_tool("skills_context", {"skills": ["demo"], "max_chars": 100000})
        print("CONTEXT_HAS_SHA=" + str("Full-file SHA256:" in text(r)))
        r = await c.call_tool("skills_context", {"skills": ["demo"], "max_chars": 300})
        print("OVERBUDGET_ERROR=" + str(r.is_error) + " SAYS=" + str("Nothing was truncated" in text(r)))
        r = await c.call_tool("skills_find", {"query": ""})
        print("EMPTYQUERY_ERROR=" + str(r.is_error))
        try:
            await c.call_tool("skills_nothing", {})
            print("UNKNOWN_TOOL=accepted")
        except Exception as e:  # the SDK raises for a protocol error
            print("UNKNOWN_TOOL=" + type(e).__name__)
        rl = await c.list_resources()
        uris = sorted(str(x.uri) for x in rl.resources)
        print("RESOURCES=" + str(len(uris)))
        pdf = [u for u in uris if "pdf-processing/SKILL.md" in u]
        print("RESOURCE_PDF=" + (pdf[0] if pdf else "missing"))
        rt = await c.list_resource_templates()
        print("TEMPLATES=" + ",".join(t.uri_template for t in rt.resource_templates))
        if pdf:
            rd = await c.read_resource(pdf[0])
            body = rd.contents[0].text
            print("READ_PDF_LEN=" + str(len(body.encode())))
        try:
            await c.read_resource("skill://system/user/pdf-processing/../../x")
            print("TRAVERSAL=accepted")
        except Exception as e:
            print("TRAVERSAL=" + type(e).__name__)
        if mode == "legacy":  # ping is removed from the 2026-07-28 protocol
            await c.send_ping()
            print("PING=ok")

asyncio.run(main())
