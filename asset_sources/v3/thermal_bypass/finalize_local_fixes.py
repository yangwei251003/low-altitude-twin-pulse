"""Bounded v2 corrections: neutral thermometer and joined rear duct plate.
No other geometry changes. Canonical builder contains the identical corrections.
"""
from pathlib import Path
import bpy,ast,math,json,hashlib,struct,zlib
import numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent;OUT=ROOT/'assets/v3/thermal_bypass';TEX=SRC/'textures';EVID=SRC/'evidence';PIVOT=(-.70,1.00,.68)
code=(SRC/'build_thermal_bypass.py').read_text(encoding='utf-8')
funcs=[n for n in ast.parse(code).body if isinstance(n,ast.FunctionDef) and n.name in ('bp','sha','png','material')]
exec(compile(ast.Module(body=funcs,type_ignores=[]),str(SRC/'build_thermal_bypass.py'),'exec'))
bpy.ops.wm.open_mainfile(filepath=str(SRC/'thermal_bypass.blend'))
scene=bpy.context.scene;source=bpy.data.collections['Editable_ThermalBypass'];root=bpy.data.objects['ThermalBypass'];pivot=bpy.data.objects['FanRotor'];parts=[o for o in source.objects if o.type=='MESH']
prior=json.loads((EVID/'build_report.json').read_text(encoding='utf-8'));groups={k:[bpy.data.objects[n] for n in ns] for k,ns in prior['source_groups'].items()}
old=bpy.data.materials['TB_StatusLens'];old.name='OLD_StatusLens';mats={}
new=material('TB_StatusLens',(.84,.86,.84),0,.22,'status')
for o in groups['StatusLens']:
    for slot in o.material_slots:
        if slot.material==old:slot.material=new
bpy.data.materials.remove(old)
# Purge only orphan images from the replaced status material, preserving 24 maps.
for im in list(bpy.data.images):
    if im.users==0 and im.source=='FILE':bpy.data.images.remove(im)
o=bpy.data.objects['FanRearCavity']
for v in o.data.vertices:v.co.x*=.70/.623;v.co.z*=.70/.623;v.co.y*=.04/.035
o.location=bp((-.70,1,.20));o.data.update()
mats={n:bpy.data.materials[n] for n in ['TB_BluePaint','TB_IvoryPaint','TB_DarkSteel','TB_CopperHeat','TB_SafetyWear','TB_StatusLens']};markers={'InteractionCentre':(0,1,0),'BaseOrigin':(0,0,0)}
bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'thermal_bypass.blend'))
exec(compile(code[code.index('# Copies only:'):],str(SRC/'build_thermal_bypass.py'),'exec'))
