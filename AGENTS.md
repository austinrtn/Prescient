# What is Prescient?
Prescient is an ECS engine that is being developed in Zig by me, myself, and I, and is still a total work in
progress.

The premise of Prescient is threefold:
- No runtime dynamic dispatch
- Comptime Components, Systems, and Entity Pools
- Use what is known at comptime to the engine's advantage for better performance
    and configurability

At the intersection of these constraints and Zig's own unique compile-time capabilities is where
novel, type-safe and performant game engine architecture is to be found... hopefully.

The products of these constraints:
- Entity Pools with configurable storage strategies
- Queries with comptime pool mappings (WIP)
- Comptime-generated dependency graph for system multithreading (WIP)

The theoretical outcomes:
- Comptime dependency graph could reduce a lot of the overhead that is seen in engines like Bevy
- Query times should be faster than other engines' query times since there is less data for queries to
    search through thanks to pool mapping
- Allowing users to select the storage strategy of different pools will allow them to optimize for
    either iteration speeds or storage-manipulation speeds (creating / deleting entities and components),
    allowing users to not have to choose one bottleneck over another.
- Scales with complexity. Because the data is functionally partitioned between entity pools, this should
    encourage data to be organized in more efficient, CPU-friendly ways. Every pool manages its own data,
    and every other aspect of the engine interacts with entity pools instead of the global storage structure
    where all entities typically exist in game engines. Because of this organization, this should
    result in the complexity of a program built with this engine to "spread out" instead of the stress being
    localized in one storage structure.

While these outcomes are unproven and would benefit only niche use cases in the best of circumstances, I am
determined to build this if for no other reason than to learn for myself and to test the limits and
capabilities of Zig's comptime.

Another goal is for the API to be simple and uniform.  Two Entity Pools with two different storage structures 
should be able to be interacted with by the user identically.  The *PoolInterface* should act as the medium 
between the messy, unpredictable inputs of the user and the deeply structured, type strict architecture
that is far too complex for the user to manage themselves.

# Definitions
## Prescient-Specific Concepts
- **Entity Pool**: Also known as EntPool or Pool, Entity Pools are storage structures used to
    house Entity-Component data, and are defined by their *component subset* and *storage strategy.*
    Instead of one global storage where all Entity-Component data lives,
    imagine that the data is partitioned into sub-storage structures instead.
    The component subset and storage strategy determine the internal makeup of which component data can be
    stored and how it gets stored. Entities are **bound** to the pool they are created in.
    While EntityPools can be used to represent whatever the user intends, it is recommended that
    Entity Pools represent types of entities as opposed to context-based representation
    (Ex. An Entity Pool dedicated to Skeleton types of entities rather than a Level 1 Entity pool which houses
    all entities within a level).
- **Storage Strategy**: A *PoolDescriptor* parameter that determines the internal layout of the component data
    storage. Users can select pools to have either an *archetype* or *sparse-set* component storage layout.
- **Component Scope**: The range of component types an Entity Pool or Query can store and manipulate
- **Global Pool**: An entity pool that can contain any and all components. It will be generated and treated
    as any other user-defined Entity Pool, and is recommended to be used for prototyping, or for one-off
    entities that don't warrant their own Pool.

## Build Time (Defined by User / Registry)
- **Global Registry**: The file in which the user defines which components, entity pools, and systems (WIP) exist within the engine. Not to be confused with the *registry files*
- **Typed Index Types**: Used for indexing storage types throughout the infrastructure. Used for type safety
    and increased code readability by giving a name to what types of data are being indexed into.
    While the user is not supposed to create or change TypedIndexes, they are found in the Global Registry
    and can have their inner type changed for less memory usage (for instance, changing a
    TypedIndex value type from u32 to u16).
- **Component Descriptors**: Names and typedefs of components used for generating Global Components.
- **Pool Descriptors**: Names, pool components / component subset, and storage strategy of an Entity Pool.
    Used for the actual generation of Entity Pools.
- **Query Descriptors**: WIP
- **Systems**: WIP, and the least fleshed-out concept within Prescient at the moment. While what Systems look
    like within Prescient will be largely determined by how the rest of the engine is built out, Systems knowing
    which components get queried read-only vs read and write could allow for the generation of a comptime
    dependency graph

## Generated at Comptime
- **Sub-Registries**: Refers to structures such as the Component and EntityPool registry. Generates all the
    data types, mappings, and other tools used throughout the engine.
- **Global Components**: Enum containing all components, represented by names, that is generated during comptime and used to generate *component subsets*.
- **Pool Components / Component Subset**: Subsets of the Global Component Enum that are generated specifically for
    each EntityPool, sub-structures within the pool, and queries as well (WIP).
    Determines which component data is allowed to be stored within the pool, and creates a type-safe
    environment that will cause attempts to interact with the pool using non-listed components to result in a
    crash, often at comptime.
- **Query Maps (WIP)**: Queries are used to find entity-component data for the user to read and write to.
    Because both component scopes of Entity Pools and queries are known at comptime, queries can generate a map
    of which Entity Pools apply to the query and ignore the pools that do not. Query caching is still an
    expected feature.
- **Operation Manager**: Used to stage and flush any actions involving the creation or deletion of entities
    and components.

## Generated at Runtime
- **Groups**: A Group refers to the conceptual group an entity belongs to and is defined by an entity's
    component composition. In sparse-set entity pools, it is primarily used by queries to find
    entities faster. In archetype entity pools, it is used to refer to the archetype in which an entity exists.

## Misc
- **User / Dev**: The hypothetical person that would be using a hypothetical finished version of
    the Prescient Engine.
- **Entity-Component data**: A shorthand for the collective data that is represented by individually
    decoupled components which are conceptually unified by a single abstract Entity.
- **WIP**: Work in progress. While everything in this project is a work in progress and subject to change,
    WIP is used throughout this documentation file to signify that the subject being discussed is not yet included
    within the engine or is still in its infancy.


# Your Mission As Codex
You are a coding assistant / learning tool that is tasked with helping me develop and test Prescient.
Your aim is to help me code, not to code for me. When answering questions, do not write to the file
unless specifically asked to do so. Give explanations and reasoning to your answers. If the question itself is
concise / basic, try to keep your response concise as well. When asked to write to a file, stay on task
and do not make changes I didn't ask for. If there is something you think is necessary or helpful to add, you
may offer it as a suggestion. It is very important that I am familiar with my entire codebase, so this is why
you need to stay on task and leave any code that you would normally write in for me as a suggestion. Any
changes you do make that may be a surprise to me should be noted within your output after changes are applied.
You will also be expected to make some project-sweeping refactors as well; the same rules still apply. These
refactors are likely to be simple and already have examples of the refactor being applied to other areas of
the project. If so, then try to keep the changes you make during the refactor in line with the existing
refactor examples.

You may be asked to write code that generates output help debug, or tests in general.  Here, you have liberty
to write code without me needing to nkow or greenlight changes.  Just leave comments to help me understand
the code.  You will also be asked to take stock in the project size from time to time.  This entails counting 
how many code instructions there are (determined by semicolon), lines of code generally (with and without 
counting breaklines), switch statements, loops, and comptime generated instructions.

# Naming and API conventions
- When a function requires Registry.EntityID as a parameter, it should be the first paramter in the function
- Function parameters should not have shortened / abrivated variable names, but the actual variable names within the functions are encouraged to be abriavated to save space
