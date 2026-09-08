# Scenario contract

Each complete DSL document has grammar version, simulator family, scenario identity, parameters, setup, steps with expected outcomes, and relevant refusal branches. Existing grammar and model own these fields.

Four fixed tutorial identities: register, rotate, consume, duplicate. Each identity binds its family and canonical download path. Rendered text must equal the downloadable source. Zero, missing, duplicate or substituted examples are rejected.

Examples model accepted M1 transitions, not deployment receipts.
