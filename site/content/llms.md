# Snacklist

> Snacklist is a shared shopping list for one household: whatever one person adds, everyone else in the household sees right away, sorted by store and by your way through the shop.

Snacklist runs on iPhone, Android and in the browser. This site has German and English pages, and every page has a Markdown version at its URL plus `.md`, for example https://snacklist.app/en/guides/claude.md.

AI assistants reach a household's list through the Snacklist MCP server at https://mcp.snacklist.app (Streamable HTTP). It uses OAuth 2.1 with dynamic client registration: your human signs in with their Snacklist account and approves the connection. A personal access key from the app (More › Access) is the alternative for clients without OAuth; the same key works for the Snacklist API. To get Snacklist, your human signs up at https://snacklist.app/en (the page shows the current way to get Snacklist).
