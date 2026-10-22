"""Exercise packaged Blender's generated node registry and stereo CPU renderer."""
import bpy,json
from pathlib import Path
out=Path('/evidence');bpy.ops.wm.read_factory_settings(use_empty=False)
checked=[]
for tree_type,nodes in [('ShaderNodeTree',['ShaderNodeTexNoise','ShaderNodeBsdfPrincipled']),('GeometryNodeTree',['GeometryNodeTransform','GeometryNodeMeshCube'])]:
 tree=bpy.data.node_groups.new('LC registry check '+tree_type,tree_type)
 for name in nodes:
  node=tree.nodes.new(name);assert node.bl_idname==name;checked.append(name)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1;scene.cycles.use_denoising=False
scene.render.resolution_x=64;scene.render.resolution_y=64;scene.render.resolution_percentage=100
scene.render.use_multiview=True;scene.render.views_format='STEREO_3D';scene.camera.data.stereo.interocular_distance=0.1
scene.render.image_settings.file_format='PNG';scene.render.image_settings.views_format='INDIVIDUAL';scene.render.filepath=str(out/'stereo.png')
bpy.ops.render.render(write_still=True)
files=sorted(out.glob('stereo*.png'));assert len(files)==2,[p.name for p in files]
images=[bpy.data.images.load(str(p),check_existing=False) for p in files]
assert all(tuple(im.size)==(64,64) for im in images)
pixels=[list(im.pixels) for im in images];different=sum(a!=b for a,b in zip(*pixels));assert different>0
(out/'result.json').write_text(json.dumps({'blender_version':bpy.app.version_string,'node_types':checked,'images':[p.name for p in files],'size':[64,64],'different_channels':different,'scope':'installed package node registration and stereo CPU render, not compositor/display validation','passed':True},indent=2)+'\n')
