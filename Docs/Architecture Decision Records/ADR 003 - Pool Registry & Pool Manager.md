# The Context

With the adoption of Entity Pools came the question of how these pools were going to be accessed and managed throughout the engine. Multiple queries across multiple systems would need access to pools that were likely defined in very different parts of the project. How pools are interacted with and stored in memory would be a massive influence on performance and user experience.

# The Decision

To create an efficient, uniform, and user friendly solution to Pool management, a Pool Registry file was added, as well as a Pool Manager struct. The Pool Manager generates specific fields for each registered pool type at compile time. This approach avoids type erasure and type casting of each pool instance, both of which were strongly avoided generally through the development of Prescient. This follows a _singleton_ pattern, one instance for each pool type. Accessing pools is done with the `PoolManager.getOrCreatePool` function, which takes the pool's corresponding enum as an argument, and either returns a pointer to an already existing instance of the pool type, or creates a new instance on the heap if that pool has yet to be initialized within the Pool Manager.

The compile-time pool registry enables several optimizations: queries can determine which pools to search at compile time, pool-specific accessor functions can be generated with zero runtime dispatch, and type errors are caught during compilation rather than at runtime.

In order to implement the Pool Manager effectively, the compiler needs to know every Pool that exists before compilation so it can generate the Pool Manager's specific pool fields. The Pool Registry is a single Zig file containing three parallel data structures: pool type definitions, an array of pool types, and an enum of pool names. The parallel structure means each pool's position in the type array corresponds to its enum index. This parallel structure must be maintained manually by the user (or through tooling) to prevent compilation errors.

# Alternative Approaches

There are a few other ways Entity Pools could be managed. Instead of a compile time Pool Manager struct with pool types as fields, a hashmap containing type erased pools would have sufficed as well. While it may be fair to say that this method would be more familiar to people as it is more common practice, the complexity required to implement type-erased storage with runtime dispatch (vtables or interface wrappers) does not yield enough benefit to justify losing compile-time type safety and specialization. The biggest missed opportunity from rejecting this approach is that runtime type-erased storage would eliminate the need for a Pool Registry, which would be more convenient for users.

Another potential approach is to allow multiple instances of the same pool to be created and stored as opposed to utilizing a singleton pattern. While this approach may be somewhat more flexible, it also can be a bit more confusing, especially to newcomers. The singleton pattern provides a simpler mental model: this pool contains these entities. Also, a developer could register two pools with different names but identical configuration if they chose to do so, making the singleton pattern just as effective in this regard.

# The Trade-Offs

The biggest downside to my approach is the necessity of the Pool Registry. Requiring users to manually open the Pool Registry file and add entries makes pool experimentation less frictionless than ideal. There are a few ways to mitigate the inconvenience:

**Option 1: Build-time registry parsing**

- Parse pool definitions from the registry file and auto-update data structures before build
- Simplest solution, but still requires users to edit a specific file

**Option 2: CLI-based pool registration**

- Add Zig CLI commands to register pools without opening the registry file
- Avoids manual file editing, but requires learning commands
- Complex pool configurations may not translate well to CLI syntax

**Option 3: Project-wide pool discovery**

- Scan entire project for pool declarations and auto-generate registry at build time
- Most convenient for users, but most complex to implement
- May not scale well with large projects (every build requires full scan)
- Pool declarations scattered across files could muddy mental model of pool organization

As of now, I'm leaning toward Option 1 (build-time parsing) as it balances convenience with maintainability. The registry file remains the single source of truth for pool organization, which aids comprehension, while automated data structure synchronization removes the manual bookkeeping burden.