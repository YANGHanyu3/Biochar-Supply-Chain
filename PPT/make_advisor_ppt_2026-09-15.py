"""make_advisor_ppt_2026-09-15.py — 中文导师汇报 PPT（图表讲解版）

复用 05_PPT/assets 的模板规范（16:9、深蓝标题栏、配色），逐图讲解，
并单独用一页回答"为什么采用 300/500 两个温度"。
"""
import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE
from PIL import Image

ROOT = r"E:\hhy\Desktop\BIochar Supply Chain"
FIG = os.path.join(ROOT, "06_Model_LaTeX", "paper_draft", "figures")
OUT = os.path.join(ROOT, "05_PPT", "2026-09",
                   "汇报_图表讲解_2026-09-15.pptx")

DARK_BLUE = RGBColor(0x1B, 0x3A, 0x5C)
MED_BLUE = RGBColor(0x2C, 0x5F, 0x8A)
LIGHT_BLUE = RGBColor(0xD6, 0xE8, 0xF7)
ACCENT = RGBColor(0xE0, 0x7A, 0x3D)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
BLACK = RGBColor(0x00, 0x00, 0x00)
DARK_GRAY = RGBColor(0x33, 0x33, 0x33)
MED_GRAY = RGBColor(0x66, 0x66, 0x66)
LIGHT_GRAY = RGBColor(0xF2, 0xF2, 0xF2)
GREEN = RGBColor(0x27, 0xAE, 0x60)
RED = RGBColor(0xC0, 0x39, 0x2B)
YELLOW_BG = RGBColor(0xFD, 0xF2, 0xE9)
CJK = "微软雅黑"

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)


def add_rect(slide, l, t, w, h, color, border=None):
    s = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, l, t, w, h)
    s.fill.solid(); s.fill.fore_color.rgb = color
    if border:
        s.line.color.rgb = border; s.line.width = Pt(0.75)
    else:
        s.line.fill.background()
    return s


def tb(slide, l, t, w, h, text, size=12, bold=False, color=BLACK,
       align=PP_ALIGN.LEFT):
    box = slide.shapes.add_textbox(l, t, w, h)
    tf = box.text_frame; tf.word_wrap = True
    p = tf.paragraphs[0]; p.text = text
    p.font.size = Pt(size); p.font.bold = bold
    p.font.color.rgb = color; p.font.name = CJK; p.alignment = align
    return box


def ml(slide, l, t, w, h, lines, size=11, color=DARK_GRAY, sp=1.15):
    box = slide.shapes.add_textbox(l, t, w, h)
    tf = box.text_frame; tf.word_wrap = True
    for i, ln in enumerate(lines):
        text = ln[0] if isinstance(ln, tuple) else ln
        bld = ln[1] if isinstance(ln, tuple) and len(ln) > 1 else False
        fs = ln[2] if isinstance(ln, tuple) and len(ln) > 2 else size
        cl = ln[3] if isinstance(ln, tuple) and len(ln) > 3 else color
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = text; p.font.size = Pt(fs); p.font.bold = bld
        p.font.color.rgb = cl; p.font.name = CJK
        p.space_after = Pt(fs * (sp - 1) * 0.5)
    return box


def header(slide, title, sub=None):
    add_rect(slide, Inches(0), Inches(0), Inches(13.333), Inches(1.05), DARK_BLUE)
    tb(slide, Inches(0.5), Inches(0.10), Inches(12.4), Inches(0.5), title,
       size=24, bold=True, color=WHITE)
    if sub:
        tb(slide, Inches(0.5), Inches(0.60), Inches(12.4), Inches(0.4), sub,
           size=12, color=RGBColor(0xBB, 0xCC, 0xDD))


def page_no(slide, n):
    tb(slide, Inches(12.5), Inches(7.05), Inches(0.7), Inches(0.3), str(n),
       size=9, color=MED_GRAY, align=PP_ALIGN.RIGHT)


def pic_fit(slide, path, l, t, max_w, max_h, caption=None):
    """Insert an image scaled to fit (max_w, max_h) inches, preserving aspect."""
    if not os.path.exists(path):
        tb(slide, l, t, max_w, Inches(0.4), "[缺少图片] " + os.path.basename(path),
           size=11, color=RED)
        return
    iw, ih = Image.open(path).size
    ar = iw / ih
    w, h = max_w, max_w / ar
    if h > max_h:
        h, w = max_h, max_h * ar
    slide.shapes.add_picture(path, l, t, Inches(w), Inches(h))
    if caption:
        tb(slide, l, t + Inches(h) + Inches(0.02), max_w, Inches(0.28), caption,
           size=9, color=MED_GRAY)


def table(slide, l, t, widths, headers, rows, size=9, header_color=DARK_BLUE):
    shp = slide.shapes.add_table(len(rows) + 1, len(headers), l, t,
                                 sum(widths), Inches(0.32 * (len(rows) + 1)))
    tbl = shp.table
    for ci, w in enumerate(widths):
        tbl.columns[ci].width = w
    for ci, htxt in enumerate(headers):
        c = tbl.cell(0, ci); c.text = htxt
        for p in c.text_frame.paragraphs:
            p.font.size = Pt(size); p.font.bold = True
            p.font.color.rgb = WHITE; p.font.name = CJK
            p.alignment = PP_ALIGN.CENTER
        c.fill.solid(); c.fill.fore_color.rgb = header_color
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            c = tbl.cell(ri + 1, ci); c.text = str(val)
            for p in c.text_frame.paragraphs:
                p.font.size = Pt(size - 1); p.font.name = CJK
                p.alignment = PP_ALIGN.CENTER if ci else PP_ALIGN.LEFT
            c.fill.solid()
            c.fill.fore_color.rgb = LIGHT_GRAY if ri % 2 == 0 else WHITE
    return shp


# ============================================================ 1 封面
s = prs.slides.add_slide(prs.slide_layouts[6])
add_rect(s, Inches(0), Inches(0), Inches(13.333), Inches(7.5), DARK_BLUE)
add_rect(s, Inches(1.4), Inches(2.75), Inches(10.5), Inches(0.04), ACCENT)
tb(s, Inches(1.4), Inches(1.5), Inches(10.5), Inches(1.1),
   "威斯康星生物炭供应链：碳政策设计", size=36, bold=True, color=WHITE)
tb(s, Inches(1.4), Inches(3.0), Inches(10.5), Inches(0.7),
   "市场出清 · 影子碳价 · 技术选择", size=22, color=RGBColor(0xBB, 0xCC, 0xDD))
tb(s, Inches(1.4), Inches(4.1), Inches(10.5), Inches(0.5),
   "导师汇报 ｜ 2026 年 9 月 15 日", size=16, color=RGBColor(0x99, 0xAA, 0xBB))
tb(s, Inches(1.4), Inches(5.4), Inches(10.5), Inches(1.0),
   "72 个县 ｜ 13 类原料 ｜ 两种热解温度（300 / 500 °C）\n"
   "数据来源：DOE BT23 (2023) + USDA NASS (2022) + USFS FIA",
   size=14, color=RGBColor(0x88, 0x99, 0xAA))

# ============================================================ 2 提纲
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "汇报提纲", "本次重点：逐图讲解 + 回答温度选择的依据")
items = [
    ("1", "研究框架总览", "系统边界：原料 → 工厂 → 生物炭 → 四类买家；碳信用如何产生"),
    ("2", "为什么是 300 / 500 两个温度", "回应导师意见：只做 300 °C 会丢掉整条碳政策主线"),
    ("3", "基准情景：不施政策会发生什么", "工厂选址、收支结构、市场均衡点 2.30 Mt"),
    ("4", "空间价值与真正的瓶颈", "各县影子价格；秸秆几乎不值钱 → 缺的是需求不是原料"),
    ("5", "三套政策的响应对比", "基准线信用 / 总量控制 / 阶梯税 + H/C 门槛"),
    ("6", "技术选择机制", "什么时候该把温度从 300 升到 500 °C"),
    ("7", "稳健性与结论", "敏感性、求解质量认证、下一步计划"),
]
for i, (n, t, d) in enumerate(items):
    y = Inches(1.35) + Inches(0.78) * i
    c = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(0.75), y, Inches(0.42), Inches(0.42))
    c.fill.solid(); c.fill.fore_color.rgb = DARK_BLUE if i < 5 else MED_BLUE
    c.line.fill.background()
    p = c.text_frame.paragraphs[0]; p.text = n
    p.font.size = Pt(15); p.font.bold = True; p.font.color.rgb = WHITE
    p.font.name = CJK; p.alignment = PP_ALIGN.CENTER
    tb(s, Inches(1.4), y - Inches(0.03), Inches(5.0), Inches(0.3), t,
       size=14, bold=True, color=DARK_BLUE)
    tb(s, Inches(1.4), y + Inches(0.26), Inches(11.0), Inches(0.38), d,
       size=10.5, color=MED_GRAY)
page_no(s, 2)

# ============================================================ 3 研究框架（图1）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "研究框架总览（图 1）", "系统边界与三套政策的碳核算口径")
pic_fit(s, os.path.join(FIG, "fig0_superstructure.png"),
        Inches(0.35), Inches(1.2), 5.6, 5.55)
ml(s, Inches(6.15), Inches(1.35), Inches(6.9), Inches(5.4), [
    ("面板 I：物料与碳的流向", True, 13, DARK_BLUE),
    ("• 13 类原料（玉米秸秆、木屑等）在 72 个县收集", False, 10.5),
    ("• T1 脱水 → T2 热解（分 300 / 500 °C 两条路线）", False, 10.5),
    ("• 生物炭卖给四类买家：H（$800，0.8 Mt，企业买碳信用）、"
     "M（$500，1.5 Mt）、L（$250，2.5 Mt）、sink（$30，建材过滤）", False, 10.5),
    ("• 虚线向上是「碳信用」流：只有 H/C ≤ 0.7 的炭才发", False, 10.5),
    ("", False, 6),
    ("面板 II：三套政策为什么要分开画", True, 13, DARK_BLUE),
    ("• 它们的碳核算口径完全不同，画在同一张流程图里会误导", False, 10.5),
    ("• A 基准线信用：只要生产就发，额度 = B − E⁺ + |S|，无门槛", False, 10.5),
    ("• B 总量控制：排放 E⁺ ≤ 上限 CAP", False, 10.5),
    ("• C 阶梯税 + H/C 门槛：只有合格炭发信用", False, 10.5),
    ("• 每格下部虚线标出该政策的「约束边界」；最右是符号表", False, 10.5),
    ("", False, 6),
    ("一句话：这张图定义了模型边界，也是后面所有结论的前提。",
     True, 11, ACCENT),
])
page_no(s, 3)

# ============================================================ 4 为什么 300/500（核心页）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "为什么采用 300 °C 与 500 °C 两个温度？",
       "回应导师意见「只考虑 300 °C 低温热解」—— 扩展的依据与代价")

add_rect(s, Inches(0.4), Inches(1.2), Inches(12.5), Inches(0.62), YELLOW_BG)
ml(s, Inches(0.6), Inches(1.26), Inches(12.1), Inches(0.5), [
    ("结论先行：只做 300 °C 的话，碳移除这条研究主线无法成立 —— "
     "300 °C 生物炭在现行方法学下拿不到任何碳信用。", True, 12.5,
     RGBColor(0x8B, 0x45, 0x13)),
])

tb(s, Inches(0.4), Inches(1.95), Inches(6.2), Inches(0.3),
   "理由一：碳信用资格（最关键）", size=13, bold=True, color=DARK_BLUE)
ml(s, Inches(0.55), Inches(2.28), Inches(6.0), Inches(1.5), [
    ("• Verra VM0044 要求摩尔 H/C ≤ 0.7 才签发碳移除信用", False, 10.5),
    ("• 300 °C 炭属「类半焦」(torrefaction-like)，实测 H/C = 0.9–1.4 → 全部不合格", False, 10.5),
    ("• 500 °C 炭 H/C = 0.40–0.52 → 全部合格", False, 10.5),
    ("• 若只保留 300 °C，模型中所有碳信用收入为 0，政策分析无从谈起", True, 10.5, RED),
])

tb(s, Inches(6.9), Inches(1.95), Inches(6.1), Inches(0.3),
   "理由二：高端市场需求", size=13, bold=True, color=DARK_BLUE)
ml(s, Inches(7.05), Inches(2.28), Inches(5.9), Inches(1.5), [
    ("• $800/吨的 CDR 溢价市场（企业采购碳移除）要求耐久性", False, 10.5),
    ("• 只有低 H/C 的 500 °C 炭能进入这个市场", False, 10.5),
    ("• 300 °C 炭只能卖给 $250–500 的农用/工业介质市场", False, 10.5),
    ("• 所以「烧多少度」直接决定产品能卖给谁", False, 10.5),
])

tb(s, Inches(0.4), Inches(3.85), Inches(6.2), Inches(0.3),
   "理由三：300 °C 的固碳持久性本身存疑", size=13, bold=True, color=DARK_BLUE)
ml(s, Inches(0.55), Inches(4.18), Inches(6.0), Inches(1.5), [
    ("• 论文采用的 ρ₃₀₀ = 0.65 取自 IPCC / VM0044 的 350–450 °C 档", False, 10.5),
    ("• 低于 350 °C 的炭，持久性可能更低（论文已明确标注该不确定性）", False, 10.5),
    ("• 即：「300 °C 能固定碳 100 年」这一说法，证据反而更弱", False, 10.5),
])

tb(s, Inches(6.9), Inches(3.85), Inches(6.1), Inches(0.3),
   "理由四：两者构成真实的经济权衡（论文核心机制）", size=13, bold=True, color=DARK_BLUE)
ml(s, Inches(7.05), Inches(4.18), Inches(5.9), Inches(1.5), [
    ("• 300 °C：产率高（0.38 vs 0.30 t/t）、成本低，但拿不到碳钱", False, 10.5),
    ("• 500 °C：产率低，但能拿碳钱 + 进高端市场", False, 10.5),
    ("• 于是温度不再是工程常数，而是由碳价决定的经济决策", True, 10.5, ACCENT),
    ("• 这正是论文最有价值的发现：碳政策门槛如何改变技术路线", False, 10.5),
])

table(s, Inches(0.4), Inches(5.85),
      [Inches(1.5), Inches(1.6), Inches(2.3), Inches(2.6), Inches(4.0)],
      ["路线", "产率 (t/t)", "H/C 实测", "碳信用资格", "产品可进入的市场"],
      [["300 °C", "0.38", "0.9 – 1.4", "不合格（全部）", "农用 / 工业介质（$250–500）"],
       ["500 °C", "0.30", "0.40 – 0.52", "合格（全部）", "CDR 溢价 + 农用 + 工业（$250–800）"]],
      size=9)

add_rect(s, Inches(0.4), Inches(6.85), Inches(12.5), Inches(0.5), LIGHT_BLUE)
tb(s, Inches(0.6), Inches(6.9), Inches(12.1), Inches(0.4),
   "诚实说明：模型把温度当作两条离散路线比较，不是连续优化；"
   "中间温度与竞争技术（气化、水热碳化）未建模，已写入论文局限性。",
   size=9.5, color=DARK_BLUE)
page_no(s, 4)

# ============================================================ 5 基准情景（图2）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "基准情景：不施政策会发生什么（图 2）", "近中期 · 无政策 · 系统最优布局")
pic_fit(s, os.path.join(FIG, "fig2_baseline.png"),
        Inches(0.35), Inches(1.2), 12.6, 3.5)
ml(s, Inches(0.4), Inches(4.85), Inches(6.2), Inches(2.2), [
    ("面板 I — 地图：工厂建在哪", True, 12, DARK_BLUE),
    ("• 颜色深浅 = 该县可收集生物质总量；圆圈 = 脱水厂，菱形 = 热解厂", False, 10),
    ("• 工厂全部集中在**中部与南部玉米带**——那里原料最便宜，就近加工省运费", False, 10),
    ("• 标注了设施最多的 6 个县（Barron / Chippewa / Clark / Dane 等）", False, 10),
])
ml(s, Inches(6.9), Inches(4.85), Inches(6.1), Inches(2.2), [
    ("面板 II — 收支：钱从哪来到哪去", True, 12, DARK_BLUE),
    ("• 生物炭销售 +1390，买原料 −322，运营 −228，运输 −37，设备年化 −95", False, 10),
    ("• 净剩 708 M$/年", False, 10),
    ("面板 III — 市场均衡：做多少就停", True, 12, DARK_BLUE),
    ("• 阶梯需求：0–0.8 Mt 出 $800；0.8–2.3 Mt 出 $500；2.3–4.8 Mt 只出 $250", False, 10),
    ("• 均衡点 2.30 Mt：再做一吨的成本已超过 $250 的买价，于是停产", True, 10, ACCENT),
])
page_no(s, 5)

# ============================================================ 6 空间价值（图3）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "空间价值与真正的瓶颈（图 3）", "质量平衡约束的对偶变量 = 各节点的「影子价格」")
pic_fit(s, os.path.join(FIG, "fig3_inherent_values.png"),
        Inches(0.35), Inches(1.2), 12.6, 3.4)
ml(s, Inches(0.4), Inches(4.75), Inches(12.3), Inches(2.3), [
    ("什么是「影子价格」？问模型：某个县再多给我 1 吨生物炭，我总共能多赚多少钱？这个数就是该县的影子价格。"
     "它不是市场挂牌价，而是在当前布局下的边际价值。", False, 10.5),
    ("", False, 5),
    ("面板 I：各县生物炭影子价格 $305–345/吨 —— 同样的炭，在不同位置价值不同。", False, 10.5),
    ("面板 II（关键）：玉米秸秆的影子价格只有 $39–77/吨，远低于农场卖价，其他原料几乎为 0。", True, 10.5, RED),
    ("　　　 → 说明原料本身不缺：再多给原料也赚不到钱。", False, 10.5),
    ("面板 III：县 × 原料 供给热力图。玉米秸秆一条独大（模型 13 类原料中，近中期实际有产量的 9 类），"
     "这解释了工厂为何扎堆玉米带。", False, 10.5),
    ("", False, 5),
    ("结论：瓶颈在需求端，不在原料端。这是后面所有政策分析的出发点。", True, 11.5, ACCENT),
])
page_no(s, 6)

# ============================================================ 7 三政策（图4）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "三套政策的响应对比（图 4）", "A 基准线信用 · C 阶梯税 + H/C 门槛 · B 排放上限")
pic_fit(s, os.path.join(FIG, "fig4_policy.png"),
        Inches(0.35), Inches(1.2), 7.4, 5.5)
ml(s, Inches(7.95), Inches(1.35), Inches(5.1), Inches(5.4), [
    ("面板 I / II：同样发钱，效果差 4 倍", True, 12, DARK_BLUE),
    ("• A（信用）把产量从 2.3 推到 2.85 Mt，盈余 708 → 3361 M$", False, 10),
    ("• C（带 H/C 门槛）产量几乎不动，盈余只到 1141 M$", False, 10),
    ("• 原因：门槛只奖励「合格炭」，不奖励「多生产」", False, 10),
    ("", False, 5),
    ("面板 III：减排到底有多贵", True, 12, DARK_BLUE),
    ("• 横轴 = 少排多少吨，纵轴 = 少排一吨要花多少钱", False, 10),
    ("• 本系统减排一吨要 $351–599", False, 10),
    ("• 而真实碳市场：RGGI $17–25、EU ETS €50–90", False, 10),
    ("• → 「惩罚排放」在这个系统里既贵又无效", True, 10, RED),
    ("", False, 5),
    ("面板 IV：技术组合怎么变", True, 12, DARK_BLUE),
    ("• $0–50 全是 300 °C；$100 起全部转为 500 °C", False, 10),
    ("", False, 5),
    ("核心结论：政策设计比政策力度更重要。", True, 11.5, ACCENT),
])
page_no(s, 7)

# ============================================================ 8 技术机制（图5）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "技术选择机制：什么时候该升温（图 5）", "信用率怎么算 · 交叉价在哪里")
pic_fit(s, os.path.join(FIG, "fig5_credit_basis.png"),
        Inches(0.35), Inches(1.2), 12.6, 3.3)
ml(s, Inches(0.4), Inches(4.65), Inches(6.2), Inches(2.4), [
    ("面板 I：两种口径算出的信用率", True, 12, DARK_BLUE),
    ("• A 口径 B − E⁺ + |S|：所有原料、所有温度都发", False, 10),
    ("• C2 口径 |S|：只有 H/C ≤ 0.7 的 500 °C 炭能拿", False, 10),
    ("• 图上明确标注：C2 下 300 °C 的柱子恒为 0（不合格）", False, 10),
])
ml(s, Inches(6.9), Inches(4.65), Inches(6.1), Inches(2.4), [
    ("面板 II：交叉价（本图最有信息量）", True, 12, DARK_BLUE),
    ("• 问：碳价多高时，改烧 500 °C 才划算？", False, 10),
    ("• 原料充裕（需求受限）时：$61/吨", False, 10),
    ("• 原料紧张（供给受限）时：$239/吨", False, 10),
    ("• 面板 III：把生物炭拆成 BC300 / BC500 两种产品后的产量构成", False, 10),
    ("一句话：温度决定能不能拿碳钱；该不该升温，取决于原料紧不紧张。", True, 11, ACCENT),
])
page_no(s, 8)

# ============================================================ 9 稳健性（图6）
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "结果稳健吗（图 6）", "单因素敏感性 + 需求二维网格")
pic_fit(s, os.path.join(FIG, "fig6_sensitivity.png"),
        Inches(0.35), Inches(1.2), 12.6, 3.6)
ml(s, Inches(0.4), Inches(4.95), Inches(12.3), Inches(2.1), [
    ("面板 I — 龙卷风图：把每个假设单独上下调 20%，看盈余变动多少。柱越长 = 越敏感。", False, 10.5),
    ("　需求价格 ±39%（最敏感）；需求容量次之；原料价格、运输成本影响很小。", False, 10.5),
    ("面板 II — 需求热力图：5×5 网格（需求量 × 需求价格），盈余从 $67 M 到 $1,406 M，"
     "两个维度都单调影响，其中价格是更大的杠杆。", False, 10.5),
    ("", False, 5),
    ("补充检验（不在本图）：求解质量认证 —— 把最差的求解点重跑到 0.1% 精度，"
     "并把扫描顺序正着跑和倒着跑各一次，结果差异 ≤ 0.2%。", False, 10.5),
    ("结论：结论对需求侧假设最敏感 —— 再次印证「需求是瓶颈」。", True, 11.5, ACCENT),
])
page_no(s, 9)

# ============================================================ 10 结论与下一步
s = prs.slides.add_slide(prs.slide_layouts[6])
header(s, "结论与下一步", "2026 年 9 月")

add_rect(s, Inches(0.4), Inches(1.25), Inches(6.1), Inches(2.6), LIGHT_BLUE)
ml(s, Inches(0.6), Inches(1.35), Inches(5.7), Inches(2.4), [
    ("三条主要结论", True, 13, DARK_BLUE),
    ("1. 需求是瓶颈，不是原料。秸秆影子价格接近零，说明多加原料也赚不到钱。", False, 10.5),
    ("2. 政策设计比政策力度更重要。发信用能扩张系统，但真正决定「烧多少度」"
     "的是 H/C 门槛。", False, 10.5),
    ("3. 惩罚排放这条政策在本系统里很贵（$351–599/吨），远高于真实碳市场，"
     "所以应当围绕「碳移除」而不是「碳排放」来设计政策。", False, 10.5),
])

add_rect(s, Inches(6.8), Inches(1.25), Inches(6.1), Inches(2.6), YELLOW_BG)
ml(s, Inches(7.0), Inches(1.35), Inches(5.7), Inches(2.4), [
    ("下一步计划", True, 13, RGBColor(0x8B, 0x45, 0x13)),
    ("1. 完成审稿意见的逐条回应（已修订 15 处、新增 4 张诊断图与 3 张表），"
     "论文改为「条件性结论」表述。", False, 10.5),
    ("2. 补齐求解质量认证与需求情景族实验（正在运行）。", False, 10.5),
    ("3. 投稿目标期刊：Computers & Chemical Engineering。", False, 10.5),
    ("4. 后续扩展：多周期与季节性库存、厌氧消化（奶业）整合。", False, 10.5),
])

tb(s, Inches(0.4), Inches(4.05), Inches(12.4), Inches(0.35),
   "需要请教导师的三个问题", size=13, bold=True, color=RED)
ml(s, Inches(0.6), Inches(4.45), Inches(12.1), Inches(2.2), [
    ("1. 温度路线的定位：是否认可「300 °C 拿不到碳信用」这一前提？"
     "若希望保留纯 300 °C 情景，可作为对比情景补充，但需明确它无法获得碳移除收入。", False, 11),
    ("2. 论文的核心主张是否收窄到「威斯康星特定参数下的条件性发现」？"
     "这是审稿意见的要求，也牺牲了一部分「普遍规律」的表述。", False, 11),
    ("3. 渠道：$800/吨的 CDR 溢价容量设为 0.8 Mt，是全国市场代理，"
     "是否需要改用更保守的采用率假设？", False, 11),
])
page_no(s, 10)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
prs.save(OUT)
print("saved:", OUT)
print("slides:", len(prs.slides))
