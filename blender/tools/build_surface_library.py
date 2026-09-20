"""Pack Codex-generated game surfaces into a reusable Blender material library."""

from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for i, (name, filename) in enumerate(
    [("Meadow", "meadow-v2-codex.png"), ("Limestone", "limestone-v2-codex.png")]
):
    m = bpy.data.materials.new(name + " / Codex v2")
    m.use_nodes = True
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(ROOT / "blender/textures" / filename))
    tex.image.pack()
    p = m.node_tree.nodes.get("Principled BSDF")
    m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.85
    m.asset_mark()
    bpy.ops.mesh.primitive_plane_add(size=4, location=(i * 4.5, 0, 0))
    bpy.context.object.name = name + " material preview"
    bpy.context.object.data.materials.append(m)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender/codex_surface_library.blend"))
