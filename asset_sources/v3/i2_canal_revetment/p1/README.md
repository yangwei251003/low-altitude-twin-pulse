# P1 可编辑护岸：静态准备

Root已批准V1参考的三施工区/修补/盐蚀方向；本入口尚未执行。等待串行CPU2窗口，预计60–120秒，私有Windows Job Object硬限300秒；日志任何独立ERROR、Error或Traceback都判失败，即使Blender返回0。

运行入口（仅获窗口后）：

```powershell
python -B asset_sources/v3/i2_canal_revetment/p1/run_preview.py --run
```

不带`--run`仅输出准备状态。本轮不烘焙、不GLB、不写运行assets、World或旧资产。

## 已借用的成熟方法

只读审过`clinic_ground/p2/build_material_p2.py`：沿用已通过审图的1.8m物理采样、原图sRGB一次转换、低反差混凝土、独立粗糙响应和中性曝光。原图来自`clinic_ground/p1/source_inputs/material_atlas_UNEDITED.png`，当前目录原字节副本SHA `11db122c63d06f7fcd25f5614f19cd0efee1b09997149071b993ed6eff7e8406`，1254²/每象限627²；没有把透视护岸参考投到墙上。

混凝土主面用较细灰象限、1.8m周期及三个施工区不同固定偏移，保70%图色；局部修补用原暖混凝土象限，不复制原铺装接缝。基色中低频干湿面按实际SourceHeight连续过渡，水线Y−1.2；噪声只在约±18mm潮缘与很弱细bump内，未增加密颗粒几何。两条锈水从实际固定点下方发源，宽4–5.5cm/长66–90cm逐渐变窄。侧面用正确竖向米制UV，避免旧地坪的XZ拉伸错误。

## 几何与输出

- 单连续闭合混凝土体，局部X±2/Y−2.8..0/Z−.35..0。显式前面阶梯拓扑做两条窄施工缝和两处35mm深固定槽；不靠贴外凸钢盒或Boolean碰运气。
- 两组埋入钢板、垫圈及六角头，最前方仍为Z−.007，全部在水侧净空平面后；固定件与槽底有实质交埋，外包不扩张。总7个编辑件，真实tri运行后报告。
- 显式`SurfaceMetric`UV及`SourceHeight/SourceX/WaterFacing`角点属性；边角真实小倒角。后续烘焙可新增BakeUV，保留材质坐标，不依赖Generated/任意世界变换。
- 预计输出`geometry_checkpoint.blend`、`i2_canal_revetment_p1.blend`、几何/图像报告以及两张PNG。图1是完整参考斜视；图2是1280×720、真实垂直26m正交跨度、固定(32,39,32)方向的单件尺寸读感，明确不是游戏光照/HUD。

## 路径与硬错误处理

源图片先解析为绝对路径，核对SHA/尺寸/真实pixel读取后的has_data，再保存checkpoint。最终源另存后才改成相对路径，重新打开实际最终blend，使用`bpy.path.abspath`解析、核对同SHA并再次读取像素后才渲图。禁止把惰性has_data当丢图，也不靠exit0当图像成功。runner扫描完整`engine.log`，缺图/ERROR一律失败；失败checkpoint和日志保留，不自动覆盖或连续重跑。

几何检查先于渲染：逐件实际evaluated闭边/体积/AABB/UV有限性、固定件水侧退距、全体精确尺寸。它不替代三角自交或实际游戏碰撞检查；模型图必须亲看后由root裁定。编辑源/纹理无丢失仍不等于最终美术通过。
