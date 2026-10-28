# Portfolio 5: Distributed and Cloud Database Exercise

## Case study
NaijaMart, a simulated e-commerce platform (see main README). This portfolio uses the MongoDB database from Portfolio 4, hosted on a free MongoDB Atlas (M0) cluster in the cloud, to examine replication, availability and consistency. Sharding is covered as a design discussion, because the free tier does not support it.

## 1. Cloud deployment
- The database runs on a managed Atlas cluster (Cluster0, free M0 tier). Atlas provisions the servers, keeps them patched and runs replication. I did not install or maintain any database server for this portfolio.
- Access is controlled in two layers: a **database user** with a password (Database Access) and an **IP allowlist** that only permits my own address (Network Access). Connections use a `mongodb+srv` connection string, which is encrypted in transit.
- The connection string contains a password, so it is kept in an environment variable and is not stored anywhere in this repository.

Evidence: `atlas_cluster_overview.png`, `atlas_network_access.png`, `atlas_database_access.png`.

## 2. Replication checks and results
`replication_checks.js` asks the cluster to describe itself, then writes and reads test records in a throwaway collection (`repl_test`), which it drops at the end so the Portfolio 4 data is untouched. Output is in `replication_output.txt`.

| Check | What it tests | Result |
|---|---|---|
| 1. Topology (`db.hello()`) | Is the cluster a replica set? | Replica set `atlas-dijrih-shard-0` with **3 members**. Primary: `shard-00-01`. Secondaries: `shard-00-00` and `shard-00-02` |
| 1. Arithmetic | How many members can fail? | A majority is 2 of 3, so **1 failure is tolerated** |
| 2. Majority write (`w: "majority"`, `j: true`) | Is a write confirmed only once most members have it? | `acknowledged: true` |
| 3. Read after write from a secondary | Can a secondary be behind the primary? | Wrote with `w: 1` (primary only), then read straight away from a secondary, 30 times: **0 stale reads out of 30** |
| 4. Which node served the read | Did a secondary really answer? | Served by `shard-00-00`; the primary was `shard-00-01`, so a **secondary** answered |

Evidence: `replication_output.txt`, `replication_output_1.png`, `replication_output_2.png`.

## 3. Analysis

**Replication.** The primary accepts every write, and the two secondaries continuously copy its changes. Every member holds a full copy of the data, so losing one server does not lose data.

**Availability.** With 3 members a majority is 2. If one member fails, the other two can still agree on a primary, so the database keeps accepting reads and writes. If a primary fails, the remaining members hold an election and promote a secondary, normally within seconds, and drivers can retry a write that was interrupted. If two members fail, the survivor cannot form a majority, so it cannot become primary and writes stop. Reads can still be served from it if the application allows secondary reads. I did not trigger a failover, because I did not find a way to do that on the free tier, so this part is explanation supported by the topology output, not an observed test.

**Consistency.**
- A write with `w: "majority"` is only confirmed after most members have it, so it survives the loss of the primary. This is the setting I would use for orders and payments.
- A write with `w: 1` is confirmed by the primary alone, so secondaries may still be catching up.
- A read from a secondary can therefore be a **stale read**: the data was correct a moment ago, but a newer version exists on the primary. For example, an order changed from PENDING to PAID could still show PENDING.
- My test found 0 stale reads in 30 tries. That does not prove stale reads cannot happen. The three members are close together, so replication took only milliseconds. It means the delay was too short for this test to catch. Replication is **eventually consistent**: secondaries are guaranteed to catch up, not to be current at every instant, and the gap can grow under load or network problems.
- Practical rule for NaijaMart: read from the primary where out-of-date data is harmful (payment status, stock, whether an order exists), and allow secondary reads where slightly old data is acceptable (browsing the catalogue, reports).

**CAP theorem.** If a network partition separates the members, MongoDB favours consistency over availability. The side that cannot reach a majority steps down and refuses writes, instead of accepting writes that could conflict with the other side. This suits orders and payments, where a wrong or duplicated record is worse than a short pause.

## 4. Sharding design for NaijaMart (discussion, not implemented)
Sharding splits one collection across several replica sets (shards), so that no single server holds all of it. The cluster here has **one** replica set and is **not sharded**. The word "shard" in the member names (`atlas-dijrih-shard-0`, `shard-00-01`) is only Atlas's naming convention. The free tier does not support sharding.

If `orders` outgrew one server, the choice of **shard key** matters most:

| Candidate key | Advantage | Problem |
|---|---|---|
| `order_date` | Easy range queries by date | Every new order has the newest date, so all writes hit one shard (a hotspot) |
| Hashed `customer.customer_id` | Spreads writes evenly; one customer's order history is found with a single targeted query | Range queries over customer IDs would have to ask every shard |
| Region or state (zones) | Keeps data close to customers in Lagos, Abuja or Port Harcourt | Uneven if one region is much busier |

My choice would be a **hashed `customer.customer_id`**, because NaijaMart's most common order query is one customer's history (Portfolio 4, part 6), and it spreads writes evenly. Reporting queries such as revenue per product (Portfolio 4, part 7) would have to read from all shards, which is acceptable for occasional reports but would be slow if run constantly. `products` is small and read-heavy, so I would leave it unsharded and rely on replication.

## 5. Comparison with PostgreSQL
My PostgreSQL database from Portfolios 1 to 3 is a single server on my laptop, so it has no replication to demonstrate. PostgreSQL supports streaming replication to standby servers, which can be used for read scaling and as a backup, but automatic failover generally needs extra tooling. A MongoDB replica set elects a new primary by itself. I did not test PostgreSQL replication.

Replication and transactions solve different problems. Portfolio 3 protected data correctness while many users change it at once. Replication protects against server failure.

## 6. Limitations of this exercise
- It ran on a free, shared cluster, so performance and configuration are limited, and automated backups and sharding are not available.
- All three members are in one region, so this tests server failure, not a whole-region outage.
- Failover was not triggered, and PostgreSQL replication was not tested.
- The stale-read test was small (30 tries) and found none, so it cannot give a figure for replication lag.

## 7. Reproduce
1. Create an Atlas cluster, a database user and a Network Access entry (see Portfolio 4).
2. Set `MONGO_URI` to the connection string.
3. Run `mongosh "$env:MONGO_URI" --file replication_checks.js`.

## 8. Files
`replication_checks.js`, `replication_output.txt`, `replication_output_1.png`, `replication_output_2.png`, `atlas_cluster_overview.png`, `atlas_network_access.png`, `atlas_database_access.png`

## 9. Reflection notes (for the final documentation)
- I expected to find at least a few stale reads and found none. I learned that "no stale reads observed" is not the same as "stale reads cannot happen", and that a test needs a second check (which node answered) before its result means anything.
- The member names contain the word "shard", which could be mistaken for a sharded cluster. Checking the topology showed one replica set.
- Some admin commands are restricted on the free tier, so I used `db.hello()` to inspect the replica set. All the checks ran without errors.