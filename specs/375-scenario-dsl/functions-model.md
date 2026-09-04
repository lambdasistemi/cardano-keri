# Functions model — #375 scenario DSL

Artifact ceiling: 4,500 bytes and 110 lines.

Signatures are contractual boundaries; implementation bodies and helpers are
outside this artifact.

## Shared grammar module

- **FUN-375-01** `assertGrammarVersion(expectedVersion: string): void`
  - Throws on any difference from exported `GRAMMAR_VERSION`.
- **FUN-375-02** `parseScenarioDsl(sourceText: string, sourceName: string): ScenarioDslDocument`
  - Returns one completely validated document or throws `ScenarioDslError`
    with source location; never returns a partial scenario.
- **FUN-375-03** `scenarioToDsl(family: ScenarioFamily, scenario: object): string`
  - Validates the family shape and returns canonical human-readable DSL.
- **FUN-375-04** `scenarioFromDsl(sourceText: string, sourceName: string): object`
  - Returns the complete existing JSON scenario value from a valid document.
- **FUN-375-05** `branchToScenario(family: ScenarioFamily, branch: ExportBranch): object`
  - Returns one checker-admissible scenario representing the selected branch.

## Page adapters

- **FUN-375-06** `loadScenarioDsl(sourceText: string, sourceName: string): void`
  - Atomically replaces the current story only after full parsing and family
    validation; otherwise reports a located diagnostic without changing it.
- **FUN-375-07** `exportCurrentBranchDsl(): string`
  - Serializes the origin-to-current-cursor branch using the shared grammar.
- **FUN-375-08** `copyCurrentBranchDsl(): Promise<void>`
  - Copies the exact value returned by FUN-375-07 or reports failure.
- **FUN-375-09** `downloadCurrentBranchDsl(): void`
  - Downloads the exact value returned by FUN-375-07 with a family-appropriate
    file name.

## Runnable compiler

- **FUN-375-10** `runScenarioDslCli(arguments: string[], stdinText: string | null): number`
  - Supports DSL-to-JSON and JSON-to-DSL with explicit family/input/output,
    produces deterministic output, and maps refusal to non-zero status plus a
    file:line diagnostic.

## Constraints

Numeric scenario literals preserve finite safe JSON numbers, including
intentionally invalid domain inputs whose refusal a story asserts. Integer
fields above JavaScript's safe-integer bound are DSL errors rather than
rounded values. All conversion functions preserve arrays, explicit `null`,
object fields, and string contents. No page, CLI, build, or proof caller
defines an alternate grammar or relaxes validation.
