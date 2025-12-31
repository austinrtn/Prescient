#!/bin/bash

# Setup Prescient with Raylib
# Usage: ./setup_prescient_raylib.sh <directory_name>

set -e  # Exit on error

# Check if directory name argument is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a directory name"
    echo "Usage: $0 <directory_name>"
    exit 1
fi

DIR_NAME="$1"
PRESCIENT_REPO="https://github.com/austinrtn/Prescient.git"
RAYLIB_URL="https://github.com/raylib-zig/raylib-zig/archive/refs/heads/devel.tar.gz"

echo "Setting up Prescient with Raylib in directory: $DIR_NAME"

# Create and enter directory
echo "Creating directory $DIR_NAME..."
mkdir -p "$DIR_NAME"
cd "$DIR_NAME"

# Clone Prescient
echo "Cloning Prescient from GitHub..."
git clone "$PRESCIENT_REPO" .

# Fetch raylib-zig bindings
echo "Fetching raylib-zig bindings..."
zig fetch --save "$RAYLIB_URL"

echo "Injecting raylib bindings into build.zig..."

# Backup original build.zig
cp build.zig build.zig.backup

# Inject raylib dependency after "const optimize = ..." line
sed -i '/const optimize = b.standardOptimizeOption/a\
\
    // Raylib dependency\
    const raylib_dep = b.dependency("raylib-zig", .{\
        .target = target,\
        .optimize = optimize,\
    });\
    const raylib = raylib_dep.module("raylib");\
    const raylib_artifact = raylib_dep.artifact("raylib");' build.zig

# Add raylib to imports - find the Prescient import line and add raylib after it
sed -i '/\.{ \.name = "Prescient", \.module = mod }/a\
                .{ .name = "raylib", .module = raylib },' build.zig

# Add linkLibrary after exe definition - find installArtifact and add before it
sed -i '/b.installArtifact(exe);/i\
    exe.linkLibrary(raylib_artifact);\
' build.zig

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  cd $DIR_NAME"
echo "  zig build run"
echo ""
echo "To use raylib in your code, import it with:"
echo "  const raylib = @import(\"raylib\");"
echo ""
echo "Note: A backup of the original build.zig was saved as build.zig.backup"
