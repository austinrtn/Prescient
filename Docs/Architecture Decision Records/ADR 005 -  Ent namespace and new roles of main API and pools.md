# Context
Having [[1.00 - Entity Pools|Entity Pools]] being solely responsible for changing entity component compositions, as well as destroying entities becomes problematic when managing systems/queries.  Since queries iterate throughout all matching pools and each pool is its own type, the compiler doesn't know which entities belong to which Entity Pools at comptime.  This means there is no reliable way to return an entity's Entity Pool, thus no way for developers to add/remove components and destroy entities within systems.  

# The Decision
1. Created a separate namespace within the main Prescient API called "Ent" which uses contains functions to manage entities and their component info.  This is-achieved by using the runtime entity_slot.pool_name data and a compile time jump table of each registered Entity Pool.  This creates a uniform, interface-like approach to handling runtime pool info.
2. Conceptually distinguish the roles of Entity Pools and the Ent namespace.  The role of entity pools is to create schemas for entities and to separate them upon creation (even though the user can still manipulate components / destroy entities via pool).  The role of the Ent namespace is to manipulate already existing entities / components, specifically in systems.  These roles should be described throughout the documentation. 

