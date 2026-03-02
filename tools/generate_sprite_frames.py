#!/usr/bin/env python3
"""Generate Godot 4 SpriteFrames .tres files for agent sprite sheets.

Layout (confirmed from NinjaAdventure source):
  64×112 image = 4 columns × 7 rows of 16×16 cells
  Columns = directions: 0=DOWN, 1=UP, 2=LEFT, 3=RIGHT
  Rows = animation frames: 0-3 = walk cycle, 4 = attack, 5 = jump, 6 = dead
"""

import os

AGENTS = ["alice", "bob", "carol", "dave", "eve"]
FRAME_W, FRAME_H = 16, 16

# Direction columns in the spritesheet
DIRS = {
    "down": 0,
    "up": 1,
    "left": 2,
    "right": 3,
}

# Animations: (name, row_indices, speed, loop)
ANIMATIONS = [
    ("walk_down",  "down",  [0, 1, 2, 3], 8.0, True),
    ("walk_up",    "up",    [0, 1, 2, 3], 8.0, True),
    ("walk_left",  "left",  [0, 1, 2, 3], 8.0, True),
    ("walk_right", "right", [0, 1, 2, 3], 8.0, True),
    ("idle_down",  "down",  [0],           1.0, False),
    ("idle_up",    "up",    [0],           1.0, False),
    ("idle_left",  "left",  [0],           1.0, False),
    ("idle_right", "right", [0],           1.0, False),
]

def generate_tres(agent_name: str) -> str:
    """Generate a Godot 4 SpriteFrames .tres file content."""
    
    # Collect all AtlasTexture sub-resources needed
    atlas_textures = []  # (id_string, col, row)
    for anim_name, dir_name, rows, speed, loop in ANIMATIONS:
        col = DIRS[dir_name]
        for row in rows:
            tex_id = f"AtlasTexture_{anim_name}_{row}"
            # Check if we already have this exact atlas texture
            if not any(t[0] == tex_id for t in atlas_textures):
                atlas_textures.append((tex_id, col, row))
    
    # Deduplicate (idle frames reuse walk frame 0)
    seen = {}
    unique_textures = []
    tex_id_map = {}  # maps (col, row) -> tex_id for reuse
    
    for tex_id, col, row in atlas_textures:
        key = (col, row)
        if key not in seen:
            seen[key] = tex_id
            unique_textures.append((tex_id, col, row))
        tex_id_map[(col, row)] = seen[key]
    
    # load_steps = 1 (ext_resource) + len(unique_textures) (sub_resources) + 1 (resource)
    load_steps = 1 + len(unique_textures) + 1
    ext_id = f"1_{agent_name}"
    
    lines = []
    lines.append(f'[gd_resource type="SpriteFrames" load_steps={load_steps} format=3]')
    lines.append('')
    lines.append(f'[ext_resource type="Texture2D" path="res://assets/sprites/agents/{agent_name}.png" id="{ext_id}"]')
    lines.append('')
    
    # Sub-resources (AtlasTextures)
    for tex_id, col, row in unique_textures:
        x = col * FRAME_W
        y = row * FRAME_H
        lines.append(f'[sub_resource type="AtlasTexture" id="{tex_id}"]')
        lines.append(f'atlas = ExtResource("{ext_id}")')
        lines.append(f'region = Rect2({x}, {y}, {FRAME_W}, {FRAME_H})')
        lines.append('')
    
    # Build animation array
    lines.append('[resource]')
    
    anim_entries = []
    for anim_name, dir_name, rows, speed, loop in ANIMATIONS:
        col = DIRS[dir_name]
        frame_entries = []
        for row in rows:
            key = (col, row)
            tex_id = tex_id_map[key]
            frame_entries.append(f'{{\n"duration": 1.0,\n"texture": SubResource("{tex_id}")\n}}')
        
        frames_str = ", ".join(frame_entries)
        loop_str = "true" if loop else "false"
        anim_entries.append(
            f'{{\n"frames": [{frames_str}],\n"loop": {loop_str},\n"name": &"{anim_name}",\n"speed": {speed}\n}}'
        )
    
    anims_str = ", ".join(anim_entries)
    lines.append(f'animations = [{anims_str}]')
    
    return '\n'.join(lines) + '\n'


def main():
    output_dir = os.path.join(
        os.path.expanduser("~/Repos/godot-agent-sim"),
        "assets", "sprites", "agents"
    )
    os.makedirs(output_dir, exist_ok=True)
    
    for agent in AGENTS:
        content = generate_tres(agent)
        path = os.path.join(output_dir, f"{agent}_frames.tres")
        with open(path, 'w') as f:
            f.write(content)
        print(f"Generated {path}")


if __name__ == "__main__":
    main()
