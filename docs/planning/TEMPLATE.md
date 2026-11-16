# {Story code} — {short title}

<!--
The planning doc is a CONTEXT CAPSULE (method.md): a cold session with no
memory and no conversation history must be able to execute this story from this
file alone. Fill every section; write "none" rather than deleting one — an
explicit "none" is information, an absent section is a question. Delete this
comment block in the real doc.
-->

Story: `docs/roadmap.md` {Story code} (status must be 👍 Approved before this
doc is implemented). Acceptance: {AC ids}.

## Why (one paragraph)

{What is missing today, for whom, and why now. Which part of the extension —
the secure gateway, the backend side, or the governance — it serves.}

## Governing constraints

{ADRs and CLAUDE.md invariants by number, one clause each on how they bite
here. Gateway facts by `api-gateway-baseline.md` row, e.g. "A1: a
RequestAuthentication alone does not reject a request without a token".
Multi-Tenant Operator facts by row (T1–T5). Any VERIFY row this story depends
on, and whether M.0 has closed it.}

## Design

{The change at file level: charts, templates, helpers, values, schema,
admission policy — exact paths. Rendered objects shown as YAML snippets. What is
NOT changing. For any security-relevant change, the "no such parameter" guard
that keeps it un-switchable (ADR-0002).}

## Tests (red first)

{Render tests (golden fixture, schema validation, guards, the "no auth
parameter" / "scope is derived" guards) and live acceptance checks to write
BEFORE the change, with the AC id each pins, including negative cases: a call
that must stay refused (no token, wrong-API token), a resource that must stay
refused (a hand-written Gateway).}

## Out of scope

{What this story deliberately doesn't do, and where that lives. Check it
against the non-goals in `vision.md`.}

## Done means

{The roadmap Done line, plus: `make` green, golden regenerated if intended,
Chart.yaml version bumped, docs updated (which), acceptance ids passing at
which level.}
