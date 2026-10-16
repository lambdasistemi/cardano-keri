# Changed responsibilities

M-377-SOURCE owns the eleven DSL scenario trees and their compiled JSON;
source identity is the N label paired with the existing numeric family ID.
M-377-NARRATIVE owns appended canonical narrative and additive clause rows.
M-377-CONSUMERS owns only authorized count/identity guards and falsifiers in
scenario-dsl-gate, registry build, both scenario gates and both trace gates.
The checkpoint clause-fragment loop joins its scenario-count hunks; theorem
extraction and duplicate checking are reserved to #387.
M-377-GENERATED owns corpus and published page regeneration through existing
Lean drivers/builders; it consumes source trees, never defines new semantics.
Dependencies point from generated/consumer surfaces to source/narrative and
existing core/model. Data contracts are in data-model.md. No backend redesign.
