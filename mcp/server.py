import os
import psycopg2
from mcp. server. fastmcp import FastMCP

mcp = FastMCP("GreenCity MCP")
mcp.settings.host="0.0.0.0"
mcp.settings.port=8000

def get_db_connection():
    return psycopg2.connect(
        dbname=os.environ.get("DB_NAME", "greencity"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", "postgres"),
        host=os.environ.get("DB_HOST", "postgres.greencity.svc.cluster.local")
    )

@mcp.tool()
def get_events(limit: int = 10) -> str:
    """Return list of last events from database GreenCity"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, title, status FROM events ORDER BY created_at DESC LIMIT %s;", (limit,))
        events = cur.fetchall()
        cur.close()
        conn.close()

if not events:
return "Events not found"

result = "Last events: \n"
for evt in events:
result += f"- {tbl[o]}\n"
return result
except Exception as e:
return f"Database error: {str(e)}"

if __ name __==
mcp.run(transport='sse')
