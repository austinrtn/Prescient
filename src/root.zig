//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Re-export ECS modules for testing
test {
    _ = @import("ecs/ArchetypePool.zig");
    //_ = @import("ecs/ComponentRegistry.zig");
    _ = @import("ecs/PoolRegistry.zig");
    _ = @import("ecs/PoolManager.zig");
    //_ = @import("ecs/ArchetypePool.zig");
    _ = @import("ecs/PoolInterface.zig");
    _ = @import("ecs/Query.zig");
    //_ = @import("systems/MovementSystem.zig");
    _ = @import("ecs/SystemManager.zig");
    _ = @import("ecs/Prescient.zig");
}

