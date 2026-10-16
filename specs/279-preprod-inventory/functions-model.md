# Functions and public command

FUN-279-MAIN: main(argv: list[str]) -> int; CLI entrypoint, public read requests and local evidence writes only.
FUN-279-REPLAY: command `python3 scripts/preprod-checkpoint-inventory.py --manifest FILE --replay FILE --json` consumes a raw Koios UTxO JSON array and emits DATA-279-REPORT JSON on stdout. Exit 0 for fully decoded ACTIVE-only supplied rows, 3 for decoded ARMED/FROZEN rows, 2 for unresolved decode/role/input errors. Replay is explicitly not a live completeness claim.
FUN-279-LIVE: command `python3 scripts/preprod-checkpoint-inventory.py --manifest FILE --output-dir DIR` writes raw evidence and report JSON plus readable Markdown; exit 0 only for a complete no-blocker live acquisition, 3 for ARMED/FROZEN, 2 for unresolved acquisition/validation gaps. No ambient endpoint/credential configuration. Any optional test endpoint is an explicit argument and cannot be labeled live preprod.
Internal helper signatures remain owner implementation detail; challenge a required public contract change before changing it.

Clarification: TOMBSTONE yields exit 2 while its authorized migration path is unresolved, even if its datum decodes. Live output filename is report.json plus report.md. An explicit --endpoint URL is permitted solely for local deterministic transport tests; such an invocation must record that URL and live_preprod=false, never describe it as live chain evidence. Default remains the public preprod endpoint and ignores ambient credentials/configuration.
