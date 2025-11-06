ECS Architecture - Project Knowledge Document

Overview
This is a compile-time optimized Entity Component System for Zig that maximizes performance through aggressive compile-time code generation while maintaining runtime flexibility for archetype creation. The architecture is built around the concept of Archetype Pools, which serve as compile-time organizational units for runtime archetypes.

Core Philosophy
Everything is specified at compile time except archetype existence. Components, pools, queries, and access patterns are all compile-time constructs. Only the specific combination of components that actually get used, called archetypes, and the entity data itself exist at runtime.

Component System

Component Identification
Components are identified using compile-time generated bitsets. Each component gets a unique bit position assigned at compile time. Component metadata like type info, bit positions, and names are generated during compilation. Bitsets enable order one archetype matching through bitwise operations.

Component Metadata
Component registry maintains compile-time mapping of component names to types. Type information extracted at compile time for code generation. No runtime component registration overhead.

Archetype Pools

What is a Pool
A pool is a compile-time defined collection of archetypes that share a common set of possible components. Pools serve as semantic groupings like OrcPool, PlayerPool, ProjectilePool and organizational boundaries for archetype management.

Pool Structure
Each pool contains an arraylist of bitsets for fast query filtering, an arraylist of storage structs containing component data, compile-time generated accessor functions, pool-specific component signature, and query cache results.

Storage Strategies
Pools can use one of two storage strategies, chosen at compile time.

Inline Arraylists for Speed Optimization. Storage struct contains ArrayList of type fields directly for each component. 24 bytes per component slot. Zero indirection for component access. Higher memory usage but faster iteration. Best for specialized pools with less than 30 components and high iteration frequency.

Optional Pointers for Memory Optimization. Storage struct contains optional pointer to ArrayList of type fields. 8 bytes per component slot, null until allocated. One pointer dereference for component access. Lower memory usage, only allocates what's used. Best for General Pool with many possible components, or pools with sparse component usage.

The General Pool
Special pool containing all engine components. Always uses optional pointer storage to prevent memory waste. Serves as catch-all for entities that don't fit into specialized pools. Good starting point for beginners learning the system.

Archetypes

Runtime Creation
Archetypes are created at runtime when a new component combination is encountered. Each archetype represents a unique component combination within a pool. Identified by a bitset indicating which components are present.

Archetype Storage Structure
The pool maintains parallel arraylists.

Bitset Array. Lightweight array of bitsets, 8 to 16 bytes each. Used for fast query filtering without loading storage. Copied from storage structs for cache efficiency.

Storage Array. Array of storage structs containing actual component arraylists. Size depends on storage strategy, 240 to 720 plus bytes per archetype. Accessed by index after bitset matching.

Why Separate Arrays
During query filtering, we only need to check bitsets. Separating them means we can iterate through bitsets checking dozens per cache line without loading the much larger storage structs. Only when a bitset matches do we load the storage struct.

Queries

Query Creation
Queries are declared at compile time with required component types. Engine determines which pools could contain matching archetypes at compile time. Query structure is specialized and generated for the specific component combination.

Query Execution Flow
First check each relevant pool's dirty flag. If dirty, update cached results using the pool's to delete and to update lists. Iterate pool's bitset array to find matching archetypes. Cache matching archetype indices. Return cached results grouped by pool.

Query Caching
Results cached as arrays of indices per pool. Indices point to positions in pool's storage arraylist. Cache invalidation managed through dirty flags and update lists. Incremental updates avoid full cache rebuilds.

Cache Invalidation Strategy
Pools maintain a to delete list with indices of archetypes marked for removal, a to update list with mappings of indices that moved due to swap remove, and a dirty flag set when lists are non-empty.

Queries check the dirty flag first. If set, process the update lists to maintain cache consistency. At end of frame or query cycle, pools process deletions and clear lists.

Iterators

Batch Iteration Pattern
Systems typically iterate in batches per archetype. For each pool in query results, for each cached archetype index in pool, get component arrays from pool passing components and index, then for each entity in archetype process the component arrays at entity index.

Component Array Access
The pool provides type-safe accessor functions. Input is component types at compile time and archetype index at runtime. Process involves bitset validation, storage struct access, and field extraction. Output is slices to component arraylists.

No casting overhead because pool knows its storage type at compile time.

Iterator Performance Characteristics
Array indexing is about 1 cycle, a multiply-add operation. Bitset checking is single bitwise AND. Component access is direct field offset calculation. Inner loop iterates contiguous component arrays. Hardware prefetcher can predict sequential access pattern.

Type Safety and Compile-Time Guarantees

What's Checked at Compile Time
Query component types must exist in at least one pool. System component access must match declared query. Component types are strongly typed. Pool accessor functions are specialized per pool. Storage struct types are generated with correct field types.

What's Checked at Runtime
Bitset validation that component exists in archetype. Array bounds checking in debug builds. Entity handle validity.

No Runtime Type Checks Needed
Because pools own their archetypes and know their types at compile time, there's no need for runtime type identification or casting. The pool's accessor functions are already specialized for its storage type.

Entity Handles

Handle Structure
Entity handles contain pool ID indicating which pool owns this entity, archetype index indicating which archetype in that pool, and entity index indicating position within archetype's component arrays.

Size is approximately 12 to 16 bytes depending on index sizes.

Handle Updates
When entities migrate between archetypes, pool ID stays same since migration is within pool. Archetype index updates to new archetype. Entity index updates to position in new archetype.

Component Migration

Within-Pool Migration
When adding or removing components, look up entity's current archetype using handle. Compute new bitset with added or removed component. Find or create archetype with new bitset in same pool. Copy component data from source to destination storage. Update entity handle to point to new location.

Why Within-Pool is Easy
All archetypes in a pool share the same storage struct type. Copying between them is type-safe because the pool knows the type at compile time. Only need to determine which fields to copy based on bitsets.

Cross-Pool Migration
Rarely needed, but possible by copying component data between different storage struct types using component IDs to map fields. More complex but explicit operation.

Memory Layout and Cache Optimization

Pool Memory Organization
Pool owns a bitset arraylist containing bitset zero, bitset one, bitset two and so on. Also owns storage arraylist containing storage zero, storage one, storage two and so on. Index zero in both arrays refers to same archetype.

Cache-Friendly Patterns

Query Filtering. Iterate bitset array sequentially. 8 to 16 bytes per element, 32 to 64 bitsets per cache line. Minimal memory traffic during filtering. Only load storage when bitset matches.

Component Iteration. Component arraylists are contiguous. Sequential access pattern perfect for prefetching. All entities in archetype processed together. Related archetypes kept together in pool.

Storage Access. With inline arraylists you get direct field access with no indirection. With optional pointers you get one dereference and predictable branch on bitset check. Storage structs are contiguous in arraylist, loaded sequentially.

Performance Characteristics

Predictable Costs
Iteration is order entity count, linear scaling. Query matching is order archetype count but amortized to order one with caching. Component access is order one array indexing or pointer dereference. Entity migration is order component count to copy data.

Cache Efficiency
Sequential memory access for iteration. Separated bitsets avoid loading unnecessary data. Contiguous storage arrays for spatial locality. Pool scoping keeps related data together.

Runtime Overhead
No component registration. No runtime type checking. No hash map lookups for archetypes. No dynamic query construction. Minimal allocation after initialization.

Compile-Time Costs
Component metadata generation. Storage struct generation per pool. Query specialization per unique query signature. Accessor function generation per pool.

Usage Patterns

For Beginners
Start with General Pool. Create entities with components. Write systems with queries. Everything works like standard ECS.

For Advanced Users
Identify entity categories with clear component sets. Create specialized pools with appropriate storage strategies. Organize systems to work within pool boundaries. Use query caching effectively.

Best Practices
Use specialized pools for performance-critical entity types. Use General Pool for miscellaneous or prototype entities. Use inline storage for pools with less than 30 components and high iteration. Use optional pointer storage for pools with 50 plus components or sparse usage. Avoid excessive cross-pool operations.

Limitations and Tradeoffs

What You Gain
Compile-time type safety. Zero-cost abstractions. Predictable performance. Cache-friendly memory layout. Minimal runtime overhead.

What You Trade
Runtime component registration not possible. Modding requires recompilation. Entity handles are larger, 12 to 16 bytes versus single ID. Learning curve for pool concept. Compile times increase with component and pool count.

Design Boundaries
Components must be defined at compile time. Pools are semantic boundaries with migration costs. Bitset size limits component count, 64 or 128 typical. Cross-pool operations are intentionally less convenient.

Implementation Details

Swap-Remove for Density
Arrays use swap-remove to maintain density. When removing an archetype or entity, the last element swaps into the gap. This requires updating any cached indices that pointed to the moved element.

Bitset vs Index Tradeoff
Could store actual archetype objects instead of just indices, but indices are smaller, stay valid across reallocation, and the indirection cost is negligible.

Why No Anyopaque in Final Design
Originally considered type-erasing storage for generic archetype handling, but pool-scoped access with compile-time type knowledge proved simpler and faster. No casting overhead, no vtables needed.

Parallel Processing Potential
Different pools can be processed in parallel independently. Within pool, different archetypes can be processed in parallel. Contiguous arrays enable easy work partitioning. No false sharing concerns with proper alignment.

Future Considerations

Potential Optimizations
SIMD auto-vectorization for component operations. Parallel query execution across pools. Compile-time dependency graph analysis for system ordering. Query result streaming for huge entity counts.

Potential Extensions
Archetype lifecycle callbacks. Component relationship graphs. Hierarchical entities. Reactive systems triggered on component changes.

Testing Strategy
Build both inline and optional pointer storage strategies. Stress test with varied entity counts, component compositions, and query patterns. Measure iteration speed, memory usage, cache behavior, and query overhead. Let empirical data guide storage strategy recommendations for different use cases.

Key Takeaways

This architecture achieves high performance through compile-time code generation while maintaining runtime flexibility where needed. Pools are the novel organizational primitive that enables semantic grouping, query scoping, and storage strategy customization. The entire system is designed to minimize runtime overhead and maximize cache efficiency while providing strong compile-time type safety.

The result is an ECS that aims to get out of the developer's way, allowing them to focus on game logic while the engine handles entity management with minimal performance cost.
