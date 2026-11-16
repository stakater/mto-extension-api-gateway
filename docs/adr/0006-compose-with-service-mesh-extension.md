# ADR-0006: Compose with the service-mesh extension; platform-rendered gateways are the sanctioned exception

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

The service-mesh extension (east-west) refuses, at admission, tenants creating
Gateway API `Gateway`s and waypoints and setting `istio.io/use-waypoint`,
because each is a new entry point and a waypoint moves where identity is checked
(sm:ADR-0005, **J4**). This extension (north-south) **must** create exactly
those — but rendered by the platform. The service-mesh guardrail already
exempts platform identities (**X1**).

## Decision

- The gateway and waypoint are rendered by the **Template Operator identity**, a
  platform identity the service-mesh guardrail exempts. A team's **hand-written**
  `Gateway`/waypoint stays refused. The Template is therefore the only way a
  tenant gets an ingress gateway.
- **When the service-mesh extension is not installed,** this extension ships its
  own optional admission guardrail of the same shape (config `guardrail.mode`),
  so the Template is still the only path. With it installed, this guardrail is
  set `Off` to avoid two policies (**Q9**).
- The two extensions compose but neither depends on the other at install time
  (**X3**). This one governs ingress; that one governs tenant-to-tenant traffic.

## Consequences

- North-south ingress becomes as un-routable-around as the service-mesh
  extension makes east-west traffic.
- A customer can adopt either extension first; running both is the full
  trust story in both directions.
- The exemption list (platform identities) must be kept in sync between the two
  extensions' values (design §10).

## Alternatives

- **Fold the gateway into the service-mesh extension.** Rejected: north-south
  and east-west are different problems, buyers and roadmaps; a separate repo is
  cleaner (and is what Rasheed created).
- **No guardrail; rely on the Template being easier than hand-rolling.**
  Rejected: "easier" is not "only"; a team could still ship an open gateway by
  hand.
