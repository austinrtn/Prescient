[33m[1m  ⚠ unsafe-undefined[39m: [33mDo not use `undefined` as a default value
[39m[22m    ╭─[[36msrc/Prescient.zig:14:29[39m]
 [2m14[22m │     id_manager: IdManager = undefined,
    ·                             [35m[1m─────────[22m[39m
 [2m15[22m │     pool_manager: PoolManager = undefined,
    ╰────
  [36mhelp:[39m If this really can be `undefined`, do so explicitly during struct initialization.

[33m[1m  ⚠ unsafe-undefined[39m: [33mDo not use `undefined` as a default value
[39m[22m    ╭─[[36msrc/Prescient.zig:15:33[39m]
 [2m14[22m │     id_manager: IdManager = undefined,
 [2m15[22m │     pool_manager: PoolManager = undefined,
    ·                                 [35m[1m─────────[22m[39m
    ╰────
  [36mhelp:[39m If this really can be `undefined`, do so explicitly during struct initialization.

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'Registry' is declared but never used.
[39m[22m   ╭─[[36msrc/Prescient.zig:2:7[39m]
 [2m1[22m │ const std = @import("std");
 [2m2[22m │ const Registry = @import("Registry.zig").Registry;
   ·       [35m[1m────────[22m[39m
 [2m3[22m │ const CR = @import("ComponentRegistry.zig").ComponentRegistry;
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'ComponentRegistry' is declared but never used.
[39m[22m   ╭─[[36msrc/Prescient.zig:4:7[39m]
 [2m3[22m │ const CR = @import("ComponentRegistry.zig").ComponentRegistry;
 [2m4[22m │ const ComponentRegistry = CR.ComponentRegistry;
   ·       [35m[1m─────────────────[22m[39m
 [2m5[22m │ const PR = @import("PoolRegistry.zig").PoolRegistry;
   ╰────

[33m[1m  ⚠ unsafe-undefined[39m: [33mDo not use `undefined` as a default value
[39m[22m    ╭─[[36msrc/PoolManager.zig:12:28[39m]
 [2m11[22m │     allocator: std.mem.Allocator,
 [2m12[22m │     storage: PoolStorage = undefined,
    ·                            [35m[1m─────────[22m[39m
    ╰────
  [36mhelp:[39m If this really can be `undefined`, do so explicitly during struct initialization.

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'CR' is declared but never used.
[39m[22m   ╭─[[36msrc/IdManager.zig:3:7[39m]
 [2m2[22m │ const ArrayList = std.ArrayList;
 [2m3[22m │ const CR = @import("ComponentRegistry.zig").ComponentRegistry;
   ·       [35m[1m──[22m[39m
 [2m4[22m │ const PR = @import("PoolRegistry.zig").PoolRegistry;
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'Io' is declared but never used.
[39m[22m   ╭─[[36msrc/root.zig:3:7[39m]
 [2m2[22m │ const std = @import("std");
 [2m3[22m │ const Io = std.Io;
   ·       [35m[1m──[22m[39m
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'Io' is declared but never used.
[39m[22m   ╭─[[36msrc/main.zig:2:7[39m]
 [2m1[22m │ const std = @import("std");
 [2m2[22m │ const Io = std.Io;
   ·       [35m[1m──[22m[39m
 [2m3[22m │ const testing = std.testing;
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'PR' is declared but never used.
[39m[22m   ╭─[[36msrc/main.zig:6:7[39m]
 [2m5[22m │ const ComponentRegistry = @import("ComponentRegistry.zig").ComponentRegistry;
 [2m6[22m │ const PR = @import("PoolRegistry.zig").PoolRegistry;
   ·       [35m[1m──[22m[39m
 [2m7[22m │ const Registry = @import("Registry.zig").Registry;
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'Registry' is declared but never used.
[39m[22m   ╭─[[36msrc/main.zig:7:7[39m]
 [2m6[22m │ const PR = @import("PoolRegistry.zig").PoolRegistry;
 [2m7[22m │ const Registry = @import("Registry.zig").Registry;
   ·       [35m[1m────────[22m[39m
 [2m8[22m │ const EntPool = @import("EntPool.zig").EntPool;
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'EntPool' is declared but never used.
[39m[22m   ╭─[[36msrc/main.zig:8:7[39m]
 [2m7[22m │ const Registry = @import("Registry.zig").Registry;
 [2m8[22m │ const EntPool = @import("EntPool.zig").EntPool;
   ·       [35m[1m───────[22m[39m
 [2m9[22m │ const ArchStore = @import("ArchetypeStorage.zig").Archetype;
   ╰────

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'ArchStore' is declared but never used.
[39m[22m    ╭─[[36msrc/main.zig:9:7[39m]
 [2m8[22m  │ const EntPool = @import("EntPool.zig").EntPool;
 [2m9[22m  │ const ArchStore = @import("ArchetypeStorage.zig").Archetype;
    ·       [35m[1m─────────[22m[39m
 [2m10[22m │ const Prescient = @import("Prescient.zig").Prescient;
    ╰────

[33m[1m  ⚠ unsafe-undefined[39m: [33mDo not use `undefined` as a default value
[39m[22m    ╭─[[36msrc/ArchetypeStorage.zig:20:28[39m]
 [2m19[22m │         global_ids: ArrayList(u32) = .empty,
 [2m20[22m │         storage: Storage = undefined,
    ·                            [35m[1m─────────[22m[39m
 [2m21[22m │         len: usize = 0,
    ╰────
  [36mhelp:[39m If this really can be `undefined`, do so explicitly during struct initialization.

[33m[1m  ⚠ unsafe-undefined[39m: [33m`undefined` is missing a safety comment
[39m[22m    ╭─[[36msrc/ArchetypeStorage.zig:63:41[39m]
 [2m62[22m │         pub fn getFields(self: *Self) EntTypeSlices {
 [2m63[22m │             var slices: EntTypeSlices = undefined;
    ·                                         [35m[1m─────────[22m[39m
 [2m64[22m │             inline for(std.meta.fields(EntTypeSlices)) |field| {
    ╰────
  [36mhelp:[39m Add a `SAFETY: <reason>` before this line explaining why this code is safe.

[33m[1m  ⚠ unsafe-undefined[39m: [33mDo not use `undefined` as a default value
[39m[22m    ╭─[[36msrc/EntPool.zig:29:56[39m]
 [2m28[22m │         allocator: std.mem.Allocator,
 [2m29[22m │         archetypes: HashMap(CR.BitSet, HashMapValue) = undefined,
    ·                                                        [35m[1m─────────[22m[39m
    ╰────
  [36mhelp:[39m If this really can be `undefined`, do so explicitly during struct initialization.

[33m[1m  ⚠ unused-decls[39m: [33mvariable 'Component' is declared but never used.
[39m[22m   ╭─[[36msrc/EntPool.zig:8:7[39m]
 [2m7[22m │ const ArchetypeStorageT = @import("ArchetypeStorage.zig").Archetype;
 [2m8[22m │ const Component = CR.Enum;
   ·       [35m[1m─────────[22m[39m
 [2m9[22m │ const CR = ComponentRegistry;
   ╰────

[33m[1m  ⚠ unsafe-undefined[39m: [33mDo not use `undefined` as a default value
[39m[22m    ╭─[[36msrc/Query.zig:54:41[39m]
 [2m54[22m │         query_return: QueryReturnType = undefined,
    ·                                         [35m[1m─────────[22m[39m
    ╰────
  [36mhelp:[39m If this really can be `undefined`, do so explicitly during struct initialization.

[33m[1m  ⚠ unsafe-undefined[39m: [33m`undefined` is missing a safety comment
[39m[22m    ╭─[[36msrc/Query.zig:94:48[39m]
 [2m93[22m │             const arch_obj = ent_pool.getArchetype(self.arch_masks[self.arch_idx]);
 [2m94[22m │             var return_arch: QueryReturnType = undefined;
    ·                                                [35m[1m─────────[22m[39m
    ╰────
  [36mhelp:[39m Add a `SAFETY: <reason>` before this line explaining why this code is safe.

	Found [33m0[39m errors and [33m18[39m warnings across [33m12[39m files in [33m1ms[39m.
