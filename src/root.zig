//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Public API exports
pub const Prescient = @import("ecs/Prescient.zig").Prescient;

// Core ECS components
pub const ComponentRegistry = @import("ecs/ComponentRegistry.zig");
pub const EntityManager = @import("ecs/EntityManager.zig");
pub const PoolManager = @import("ecs/PoolManager.zig");
pub const SystemManager = @import("ecs/SystemManager.zig");

// Pool system
pub const PoolRegistry = @import("ecs/PoolRegistry.zig");
pub const PoolInterface = @import("ecs/PoolInterface.zig");
pub const EntityPool = @import("ecs/EntityPool.zig");
pub const ArchetypePool = @import("ecs/ArchetypePool.zig");
pub const SparseSetPool = @import("ecs/SparseSetPool.zig");

// Query system
pub const Query = @import("ecs/Query.zig");
pub const QueryTypes = @import("ecs/QueryTypes.zig");

// Builders and utilities
pub const EntityBuilder = @import("ecs/EntityBuilder.zig");
pub const MaskManager = @import("ecs/MaskManager.zig");

// Storage strategies
pub const StorageStrategy = @import("ecs/StorageStrategy.zig");

