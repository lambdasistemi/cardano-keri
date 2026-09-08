# Changed interfaces

New command: node scripts/check-architecture-scenarios.mjs [--site PATH] [--selftest].

No public library signatures change. The command consumes existing parseScenarioDsl(sourceText, sourceName) and checkScenario(scenario, label, corpus) interfaces.

Default verifies canonical sources and documentation bindings. --site also verifies actual rendered blocks and downloads. --selftest demonstrates missing-example, malformed-text and wrong-outcome rejection. Failure returns nonzero and an actionable diagnostic.
