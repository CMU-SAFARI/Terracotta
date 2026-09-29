# Workload Mixes

Shared workload mixes used by the ChargeCache, MASA, MoPAC-C, and ChargeCacheMASA case
studies (PRADA uses its own PuM-specific mixes under `techniques/prada/mixes/`).

## Single-Core
- All workloads with Row Buffer Conflicts Per Kilo Instructions > 5.0 are categorized as H and the others are categorized as L

## Four-Core
We create 20 mixes with the 4 of each of the following configurations. The workloads are picked randomly from the set of single-core workloads.
- HHHH
- HHHL
- HHLL
- HLLL
- LLLL