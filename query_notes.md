# Archetype Cache
Handles cached archetypes by creating a comptime struct containing a field for a slice
of each component within the query.  

```zig
//If we have a query of Pos + Vel, then are cache looks like: 
struct {
    pos: {pos1, pos2, pos3},
    vel: {vel1, vel2, vel3},
}
```
The cache itself isn't just stored in the query, the cache is stored within the ArchElementType

# Archetype Element
This is what orgamizes the cache by pool.  

## Fields
- pool Name
    Contains Pool Name enum

- access
    Determines how query can access the pool, **direct** or **lookup**

- Archetype_indicies
    
