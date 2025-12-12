# The Context

While the introduction of Entity Pools enabled a variety of added benefits, it also introduced some negative unintended consequences that need addressing. Entity Pools require upfront architectural decisions which discourage prototyping and restrict flexibility when adding and removing components. The ability to create new component makeups without restriction is not only trivial in other engines, but is a major selling point to developers looking to break away from the more rigidly structured OOP practices.

Entity Pools also raise the barrier to entry of Prescient by adding another layer of complexity and abstraction. Newcomers to ECS may be discouraged by having to understand pools on top of ECS fundamentals. Those already familiar with the paradigm may be put off by having to conform to an entirely different organization strategy. Generally speaking, developers enjoy the traditional ECS experience.

Users may also find it tedious to create pools for entity types that do not need their own storage container because the entity type is uncommon or only belongs to a handful of entities. This "Pool Oriented" approach can also incentivize pool proliferation: a large amount of pools that contain only small amounts of entities with only a small variety of component makeups. Pool proliferation reduces cache efficiency, and while it can be mitigated by broadening Entity Pools by allowing more component makeups, the developer won't be able to completely avoid proliferation without some form of alternative.

# The Decision

Prescient offers its users the "General Pool." The General Pool is an Entity Pool just like any other, but it is registered by default and contains all registered components within it. This means any entity created within the General Pool can have any component within the engine. This is nearly functionally identical to how components are added to entities in more traditional ECS engines, making prototyping and component flexibility just as trivial.

The General Pool aligns perfectly with Prescient's progressive disclosure philosophy. Those new to it won't need to know anything at all about pools to start developing.  Only when their project hits bottlenecks or becomes deeply unorganized will they need to understand Entity Pools. This gives newcomers to Prescient and ECS generally a beginner friendly starting point, and offers ECS veterans the familiar experience that they may be looking for.

The General Pool also makes pool proliferation completely avoidable. Entity variations that do not have enough entities to warrant their own pools can just be added to the General Pool. If they reach that threshold, the developer can simply change their pool call from `getPool(.General)` to `getPool(.NewPool)`. The API stays the exact same.

# Uniformity

General Pools are no different from Entity Pools architecturally. The same struct, same arguments, and treated the same by queries and every other aspect of Prescient. This enables uniformity across pools in every dimension, from API usage to conceptual understanding. The configuration of the General Pool can also be tweaked by the developer the same way other pools can, such as changing storage strategies, adding required components, and limiting which components are allowed. The General Pool serves dual purposes: as an entry point for development (working immediately without understanding pools) and as a learning tool (demonstrating pool behavior in a familiar context).

# The Trade-Offs

The General Pool gives Prescient's users an "easy way out." Because it's easy to access and should manage most entity types just fine, the circumstances that push users to engage with pools more deeply are admittedly rare, and even when bottlenecks are obvious, it may not be obvious that additional Entity Pools are the solution.  Users may end of blaming the engine itself for the subpar performance rather than looking to optimize with Entity Pools.  To encourage eventual pool exploration, General Pool access is kept explicit. I considered making it the default API (API.createEntity vs Pool.createEntity) or giving it a separate namespace, but instead chose to require the same getPool call as any other pool. The hope is that this unavoidable reference to pools sparks curiosity and leads developers to the documentation.

Another way Entity Pool use is encouraged is by making the General Pool use sparse-set storage by default. This storage strategy makes sense for the low-entity-count use cases the General Pool is designed for, but also means users with large homogeneous entity populations will encounter performance bottlenecks that specialized archetype pools would solve.

The opposite side of the coin is that pools are always visible in the API, even for beginners who just want to use the General Pool. Seeing `getPool(.General)` might intimidate new users or put off skeptical ECS purists. That's why providing adequate documentation is vital, both an easy beginner's guide that ignores pool concepts and in-depth Entity Pool explanations for when users are ready.

Finally, it's important to note that as the General Pool grows, the more it degrades. If Entity Pools aren't being utilized and the user depends solely on the General Pool, then the General Pool becomes just like any other sparse-set entity storage in other ECS engines, and the developer runs into many of the same issues Prescient set out to improve in the first place.