# 图标方向与生成约束（松雾折序已定版）

## 2026-11-08 最新执行版本

用户指定图1松针绿/雾灰白与完整轮廓，结合图2中央交错边缘微立体，并于 2026-11-08 明确确认“就这个版本作为我们的图标”。当前正式资源采用此组合；视觉定版不代表已完成 IPA 验收。轮廓内缩保留呼吸空间，不再扩大裁切；不增加星点、发光或整体曲面。此前所有方案保留。

生成命令：`python -B -X utf8 scripts/generate_master_app_icon.py --palette pine --style interlaced`。
本轮检验发现指数阴影无限尾部在转整数时会让大面积平色暗 1 级；现将阴影平滑收敛于 64 px 的局部范围，确保主体之外和远离交错处保留原始双色。修复前原色覆盖率断言失败（0.864 < 0.93），修复后全部 5 项资源测试通过，未降低断言。
预览为本地绘制，并非模拟器截图。已查看 600 px 大图和 120 / 60 / 40 px 缩略图；实际设备图标待后续新 SHA 构建验收。

回退到基础平面折序：`python -B -X utf8 scripts/generate_master_app_icon.py --palette pine --style flat`。此命令只重生成图标、品牌资源和预览，不修改业务代码；不是恢复艺术实验 C 的裁切版。

保留全部已有平面/艺术实验方向，不覆盖旧候选。最新偏好：桃粉苔青、松针绿雾灰白优先，克莱因蓝艾绿也认可。用户喜欢立体参考P1/P2的完成度，但要求保留撞色，避免多色融合；第三参考很帅但过于通用，必须保留专属轮廓和灵性。

## 共同要求

独立1024方形iOS图标母版，RGB不透明，完整画布不预裁透明系统圆角；无字、无水印、无设备/展示板。中心主体有明确辨认的两片折面与一个宽阔负形，避免多层互换后读不懂。40/60/120px仍有可辨认轮廓。双颜色分别属于背景和主体，不做粉绿互相混融；同色明暗可用于体积。不能用泛用发光球、宝石、莫比乌斯环或书本替代专属图形。

## 01 平面支线（保留）

已生成折序及其艺术实验变体，用户认可但希望更强视觉。保留原图，不因新增立体方向删除。原始色：FACBC6/465C47、3A6341/E8E8E4、012696/A4E2C6。

## 02 悬浮折面（P1结构参考）

Use case: logo-brand
Asset type: premium iOS app icon, 1024 x 1024 opaque full bleed
Primary request: An original, immediately recognizable folded-ribbon emblem for a literary and media reader. Two broad asymmetric sculpted planes curve around one expressive negative space, suggesting a living flowing Z without typeset lettering. One extremely restrained orbit traces the change of plane; it must not crowd or obscure the silhouette. Use asymmetry and a deliberate cut to create personality. Use the reference only for the spatial relationships and material finish; do not copy its star, glow or exact silhouette.
Color palette: strict contrasting moss #465C47 background and peach #FACBC6 sculptural object. Colours belong to separate surfaces. No blended pink-green gradient. Soft same-pigment shading allowed.
Materials/textures: satin ceramic or softly polished resin, precise edge, controlled warm studio reflection, no metallic chrome, no neon haze.
Composition: generous visible negative space, centre of mass slightly above centre, designed at 40px as well as full size. No typography or framing card.

## 03 轻盈曲面（P2结构参考）

Use case: logo-brand
Asset type: premium iOS app icon, 1024 x 1024 opaque full bleed
Primary request: An original elegant emblem composed of two broad flowing curved surfaces, a lower folded tongue and one controlled small upward flick. It should feel alive and poised, with an unexpected asymmetric cut providing recognition. Refine the fluid negative-space idea of the existing flat fold mark. Avoid generic open-book illustration and leaf logos. Reference P2 only for lightness and refined curvature, not its little sparkles or literal layered pages.
Color palette: strict pine green #3A6341 background and mist white #E8E8E4 object; maintain visible contrast with no mixed green-white gradients across surfaces. Same-color form shading only.
Materials: matte porcelain with a thin satin edge, soft restrained studio shadows. No broad bloom, ornamental stars, lens flare, glass ball, gemstone, smoke or futuristic technology clichés.
Composition: one legible object and large clean colour fields. Deliver square icon artwork only with no pre-baked rounded card, labels, watermarks or screenshot UI.

## 对照第三色

若形状与材质通过，用同一构图制作克莱因蓝012696背景/艾绿A4E2C6主体，不在比较时又换形状。

## 工具状态

本会话未提供内置image_gen。现有图标预览来自可复现的Pillow/NumPy/OpenCV几何渲染。模型图像生成需按imagegen技能走明确授权的CLI/API路径；当前进程未配置OPENAI_API_KEY。不得把几何预览描述为AI生成图。
