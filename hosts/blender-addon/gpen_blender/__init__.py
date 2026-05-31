bl_info = {
    "name": "GPen",
    "author": "local",
    "version": (0, 0, 1),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar",
    "description": "Minimal Grease Pencil host for the Zig core library.",
    "category": "Grease Pencil",
}

import bpy


class GPEN_OT_demo(bpy.types.Operator):
    bl_idname = "gpen.demo"
    bl_label = "Run GPen"

    def execute(self, context):
        self.report({"INFO"}, "GPen host placeholder")
        return {"FINISHED"}


class GPEN_PT_demo(bpy.types.Panel):
    bl_label = "GPen"
    bl_idname = "GPEN_PT_demo"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "GPen"

    def draw(self, context):
        layout = self.layout
        layout.operator("gpen.demo")


classes = (GPEN_OT_demo, GPEN_PT_demo)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)
