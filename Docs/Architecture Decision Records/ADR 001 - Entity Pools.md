# The Context

Most ECS engines take a global approach to entity storage, with all entities living in one unified memory structure, typically separated only by game state (main menu vs gameplay). While archetype systems group entities by component combinations, they don't distinguish between semantically different entity categories. An NPC with Position and Health lives alongside a UI button with the same components, even though they'll never be queried together. This broad approach to storing entity data comes with downsides. The uniform handling of all entities misses potential optimizations, configuration opportunities, and type safety enforcement.

# The Decision

Entity Pools are compile-time organizational units that semantically separate different entity types and allow independent storage configuration for each category. Instead of having one global memory structure to store entities in, the user can create individual entity containers meant to house entities of similar component makeups. Instead of having NPCs, UI elements, status effects, particles, and every other type of entity housed together in memory, Prescient allows for each of these entity types to have their own storage containers.

# What This Enables

Entity Pools unlock several capabilities impossible in traditional ECS:

- **Hybrid storage strategies**: Choose archetype storage for stable, frequently iterated entities (NPCs, enemies) and sparse set storage for high churn entities (particles, status effects) within the same project
- **Compile time query optimization**: Queries know which pools to search at compile time, eliminating unnecessary archetype checks
- **Semantic type safety**: Required components are enforced at compile time per pool; a PlayerPool can guarantee all players have Position
- **Independent scaling**: Performance critical pools can be optimized independently without affecting the rest of the system

Entity Pools enable better scaling as projects grow in complexity through partitioned storage (improved cache locality), per pool configuration (storage strategy choice), compile time query mapping (reduced search space), and enhanced type safety (required components enforcement).

# The Intuition

Entity Pools were designed with intuition in mind. They encourage familiar, class like semantic organization; `EnemyPool` and `PlayerPool` read like class declarations, making the codebase easier to navigate for developers from any background. While in some sense, Entity Pools add an extra layer of needed understanding to use, they also provide familiar semantic organization without sacrificing any performance. Developers coming from OOP may find Entity Pools to be more intuitive than the pure ECS "data soup" approach, while those already familiar with ECS can appreciate the increased control and organization pools provide.

# Compile Time Pool Types Vs. Run Time Instances
It's important to make clear the distinction between what happens at compile time vs what happens during run time.  Compile time is when the binary for the pool itself is generated based off of its configuration determined by the user.  A sparse-set pool with X, Y, and Z components is a completely different type and looks completely different at the binary level than an archetype pool with A, B, and C components.  The run time instances of these pools is where the functionality happens: adding and removing entities, adding and removing component data, data management within the pool, etc.  In short, compile time is responsible for the unique generation of pools determined by their configuration, run time generation is responsible for data storage and management.  

# The Trade Offs

Perhaps the biggest trade off is the steeper initial learning curve. As stated above, many may find them intuitive to use, but understanding the when, why and how to use and configure pools may seem overwhelming to newcomers. This is mitigated by a philosophy of _progressive disclosure_, and the introduction of the _General Pool_. Users can learn as they go, as opposed to being forced to learn all at once.

Another trade-off is pool proliferation. Having many pools each containing only a few entities can degrade cache performance; you're iterating many small memory regions instead of one large contiguous region. This is typically a result of over organization (creating a pool for every minor entity variation rather than grouping related types) and is easily avoided by combining semantically similar entities or using the General Pool for low count entity types. In practice, pools should contain hundreds to thousands of entities to justify the organizational overhead. That being said, the performance impact of pool proliferation is very difficult to quantify, and shouldn't be a problem in a vast majority of use cases. It is still a concern worth noting, and would likely be difficult to identify during profiling.  

It is also worth noting that cross-pool migration is not supported, meaning entities can not move from one pool to another.  Supporting this feature would be very complicated to implement, and actually migrating entities across pools would be computationally expensive.  There are very few use cases that would actually benefit from this, thus does not seem worth implementing for the time being.  The developer could still add their own functions to copy existing data from an entity of one pool into another.  

The final consideration is that Entity Pools encourage upfront architectural decisions. Unlike pure ECS where you can freely add any component to any entity, pools define clear boundaries with required and optional components. This structure aids large projects but can feel restrictive during rapid prototyping. The General Pool addresses this by providing a flexible space for experimentation; you can develop features there and migrate to specialized pools only when performance or organization benefits emerge. This means developers don't have to commit to any strict, defined organization structure while experimenting with components, or just adding "one off" entities into their project.

