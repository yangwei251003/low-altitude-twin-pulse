# P4 原图显式UV材质对照

**实际更新：**一次 CPU2 源三图已自然 exit0（PID41484，147.828秒），原字节读回24/24；根逐图查看后批准进入烘焙/12件GLB候选。局部短端 UV 条纹待在新交付副本修正，当前源/图冻结。[完整实测与限制](REVIEW.md)。尚无烘焙/GLB/游戏镜头或最终美术验收。下文保留运行前静态方案，所述“待运行”是历史阶段。

根已实际查看并批准单张原生imagegen钢板图进入本轮源材质对照。图实际为2172×724（3:1），保留原字节；不再为了宽高重生成。当前只静态准备，**尚未启动Blender**，没有烘焙/GLB或生产改动。P1/P2/P3原记录不动。

## 相比P3的实际变化

- `geometry.py`与P3逐字相同，SHA `6bc93dea3b77922808702957f5438ab74a587de180d5e906cfde4cdc26fcea99`；含已许可的护板脚承肩，12件/原轴/包络/2.8mm防滑/板缝不改。
- 蓝绿钢材彻底移除P3盐垢椭圆、橙色螺栓滴刷及折边椭圆。新`PaintPanelUV`将**每块真实6×1m护板**完整映射一次；竖肋按同一资产坐标采样，不在每根肋上重新铺整板。北护板U随+X，南护板U随-X；两侧构件都保持V=真实Y。
- 原图像素3:1映射6×1m，因此图形在物理面上横向伸展2倍。这是已明确接受进入对照的限制，不称原图已经6:1。先在三图看其裂痕/流痕是否仍可信。
- 底色为原图与同色完整漆混合：底部原图权重.58，上部.64；不改原图像素。局部低边梁只取上半幅较安静的窄带，所有小五金不使用这张整板。图片之外不再叠加盐/锈椭圆。
- 图片褐色/低饱和区域提供克制的作者指定粗糙/露底金属响应，完整漆仍Metallic0；这不是从底色恢复出的测量PBR。浅Bump最大.25mm，不增加真实几何或投影阴影。
- 轮轴局部油污和两柄抓握磨损保留P3位置；甲板通行带改暗色，6处擦痕也从亮白改成暗橡胶/磨擦色，粗糙度略升。真实防滑不变。

## UV与原图路径

`source_inputs/painted_steel_material_v1_UNEDITED.png`与项目参考原图完全相同，SHA `2ab3fdfab826eddf4736f92c34faeece79ff76278144a0430943a2924d6f50be`，2,631,351B。Blender加载时验证尺寸/哈希/sRGB并实际读取像素，最终报告也记录其输入哈希。不会用Python修改像素。

源四层显式UV：SurfaceUV、SourceXZ、SourceY、PaintPanelUV。蓝漆源着色器仅显式读取PaintPanelUV；其他材质继续使用SourceXZ/SourceY和WeatherUse角点属性。SurfaceUV仍为活动源投影，**不是独占烘焙图集**。将来烘焙需像泵房一样从evaluated副本保留`preserve_all_data_layers=True`，在新增DeliveryBakeUV后再次校验所有角点UV/属性；本次不进入该阶段。

## 静态与待运行

普通Python编译、原图字节/实际宽高、P3几何逐字/原12件及旧输入输出哈希检查；结果见`static_validation.json`。这些不等同为Blender材质效果通过。新图片在实际6×1护板上的尺度、暗磨擦带、下方车架和近景锁件仍待一次同机位三图。

根分配CPU2/240秒窗口后才执行，不自动追加一轮：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --threads 2 --python-exit-code 1 --python 'asset_sources/v3/shared_access_bridge_deck/p4/build_source.py' -- --render --samples 16 --output source_review_01
```

沿用P1/P2/P3相机、照明、曝光.45、1400×1050、16samples。输出可编辑源与01斜视/02车架下方/03锁件近景；原图不裁切、不遮藏失败部位、不将离线图称游戏截图。
