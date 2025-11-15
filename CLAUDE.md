- Archetypes must be run time and can not take comptime parameters
- Zig 0.15 does not init with allocators.  Instead allocators are passed through functions
- Use sacratic-tutor.txt as a guildline for answering questions and explaining code
- zig 0.15+ allocators are passed through functions in ArrayLists and are not required in init

## Query Direct/Lookup Access Pattern

Queries use a two-tier access pattern for performance optimization:

### Direct Access
- All queried components are in the pool's REQ_MASK (required components)
- Every archetype in the pool is guaranteed to have all query components
- Can iterate through the pool directly without per-archetype checks
- Most efficient access pattern

### Lookup Access
- All queried components exist in the pool's overall mask (REQ_MASK | OPT_MASK)
- At least one queried component is in OPT_MASK (optional components)
- Some archetypes may have the component, others may not
- Requires checking each archetype individually against the query mask before iteration
- Less efficient but still valid matches

The determination happens in a single loop for efficiency:
1. Start assuming both query_match and req_match are true
2. If any component doesn't exist in the pool → pool excluded entirely (break)
3. If component exists but not in REQ_MASK → req_match becomes false, continue checking remaining components
4. After checking all components: req_match = Direct, query_match only = Lookup
- Check taskwarrior tasks to get a sense of what is currently being implememnted
- I have no current plans for entities to be able to migrate into other pools.