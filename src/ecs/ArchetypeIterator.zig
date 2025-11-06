const std = @import("std");
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const ArchetypeManager = @import("ArchetypeManager.zig");

const ComponentName = ComponentRegistry.ComponentName;
const getComponentByName = ComponentRegistry.GetComponentByName;
const StructField = std.builtin.Type.StructField;
const ArchetypeCollection = ArchetypeManager.ArchetypeCollection;

pub fn ArchetypeIterator(comptime componentNames: []const ComponentName) type {
    const ComponentData = blk: {
        var fields: [componentNames.len]StructField = undefined;

        for(componentNames, 0..) |compName, i| {
            const compType = getComponentByName(compName);
            fields[i] = StructField {
                .name = @tagName(compName),
                .type = *compType,
                .alignment = @alignOf(*compType),
                .is_comptime = false,
                .default_value_ptr = null,
            };
        }

        break :blk @Type(std.builtin.Type{
            .@"struct" = std.builtin.Type.Struct {
                .layout = .auto,
                .backing_integer = null,
                .fields = &fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });
    };

    const ArchetypeBatch = blk: {
        var fields: [componentNames.len]StructField = undefined;

        for(componentNames, 0..) |compName, i| {
            const compType = getComponentByName(compName);
            fields[i] = StructField {
                .name = @tagName(compName),
                .type = []compType,
                .alignment = @alignOf([]compType),
                .is_comptime = false,
                .default_value_ptr = null,
            };
        }

        break :blk @Type(std.builtin.Type{
            .@"struct" = std.builtin.Type.Struct {
                .layout = .auto,
                .backing_integer = null,
                .fields = &fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });
    };

    return struct {
        const Self = @This();
        pub const BatchType = ArchetypeBatch;

        archetypeIndex: usize = 0,
        entityIndex: usize = 0,

        archetypes: ArchetypeCollection(componentNames),
        thread_pool: *std.Thread.Pool,
        allocator: std.mem.Allocator,

        pub fn init(archetypeManager: *ArchetypeManager.ArchetypeManager, allocator: std.mem.Allocator) !Self{
            const pool = try allocator.create(std.Thread.Pool);
            errdefer allocator.destroy(pool);

            try pool.init(.{
                .allocator = allocator,
                .n_jobs = null,
            });

            return Self{
                .archetypes = archetypeManager.queryComponents(componentNames),
                .thread_pool = pool,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.thread_pool.deinit();
            self.allocator.destroy(self.thread_pool);
        }

        pub fn next(self: *Self) !?ComponentData {
            const fields = std.meta.fields(@TypeOf(self.archetypes));

            while (self.archetypeIndex < fields.len) {
                const result: ?ComponentData = switch (self.archetypeIndex) {
                    inline 0...fields.len - 1 => |i| blk: {
                        const archetype = @field(self.archetypes, fields[i].name);

                        if (self.entityIndex < archetype.len()) {
                            var componentData: ComponentData = undefined;
                            inline for(componentNames) |compName| {
                                @field(componentData, @tagName(compName)) = archetype.getComponentData(compName, @intCast(self.entityIndex));
                            }
                            self.entityIndex += 1;
                            break :blk componentData;
                        } else {
                            break :blk null;
                        }
                    },
                    else => null,
                };

                if (result) |data| {
                    return data;
                }

                self.archetypeIndex += 1;
                self.entityIndex = 0;
            }

            self.archetypeIndex = 0;
            self.entityIndex = 0;
            return null;
        }

        pub fn nextBatch(self: *Self) ?ArchetypeBatch {
            const fields = std.meta.fields(@TypeOf(self.archetypes));

            while (self.archetypeIndex < fields.len) : (self.archetypeIndex += 1) {
                const batch: ?ArchetypeBatch = switch (self.archetypeIndex) {
                    inline 0...fields.len - 1 => |i| blk: {
                        const archetype = @field(self.archetypes, fields[i].name);
                        const len = archetype.len();
                        if (len == 0) break :blk null;

                        var result: ArchetypeBatch = undefined;
                        inline for(componentNames) |compName| {
                            @field(result, @tagName(compName)) = archetype.getComponentArray(compName);
                        }
                        break :blk result;
                    },
                    else => null,
                };

                if (batch) |b| {
                    self.archetypeIndex += 1;
                    return b;
                }
            }

            self.archetypeIndex = 0;
            return null;
        }

        pub fn executeParallel(
            self: *Self,
            comptime processFn: fn(batch: ArchetypeBatch) void
        ) !void {
            var batches: std.ArrayList(ArchetypeBatch) = .{};
            defer batches.deinit(self.allocator);

            self.reset();

            var total_entities: usize = 0;
            const fields = std.meta.fields(@TypeOf(self.archetypes));
            inline for(fields) |field| {
                const archetype = @field(self.archetypes, field.name);
                total_entities += archetype.len();
            }
            if(total_entities == 0) return;

            const threadCount = self.thread_pool.threads.len;
            const target_work_items = threadCount * 3;
            const chunk_size = @max(total_entities / target_work_items, 100);

            while(self.nextBatch()) |batch| {
                const first_field = comptime @tagName(componentNames[0]);
                const batch_count = @field(batch, first_field).len;

                if(batch_count <= chunk_size) {try batches.append(self.allocator, batch);}
                else {
                    var offset: usize = 0;
                    while(offset < batch_count) {
                        const remaining = batch_count - offset;
                        const current_chunck = @min(chunk_size, remaining);

                        var sub_batch: ArchetypeBatch = undefined;

                        inline for(componentNames) |compName| {
                            @field(sub_batch, @tagName(compName)) = 
                                @field(batch, @tagName(compName))[offset..offset + current_chunck];
                        }
                        try batches.append(self.allocator, sub_batch);
                        offset += current_chunck;
                    }
                }
            }

            if(batches.items.len == 0) return;

            var wait_group = std.Thread.WaitGroup{};
            for(batches.items) |batch| {
                wait_group.start();
                try self.thread_pool.*.spawn(struct {
                    fn work(wg: *std.Thread.WaitGroup, b: ArchetypeBatch) void {
                        defer wg.finish();
                        processFn(b);
                    }
                }.work, .{&wait_group, batch});
            }
            self.thread_pool.*.waitAndWork(&wait_group);
        }

        pub fn reset(self: *Self) void {
            self.archetypeIndex = 0;
            self.entityIndex = 0;
        }
    };
}
