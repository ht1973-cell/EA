"""スライド画像・サムネイル生成（A5/A6の図解フォールバック & A8サムネ）。

Pillow で顔出しなしの図解スライドを描く。数字・テロップ中心（設計書§9の優先順位）。
本番の Veo 映像素材が video/ にあればそちらを優先し、無ければこのスライドで確実に成立させる。
"""
import os
from PIL import Image, ImageDraw, ImageFont

# 配色（第4章の信号機モチーフと同系。落ち着いた金融トーン）
BG = (14, 20, 32)          # 紺(ほぼ黒)
FG = (232, 236, 243)       # 生成りの白
ACCENT = (57, 190, 159)    # ティール(成長)
AMBER = (224, 164, 74)     # 警告アンバー
MUTED = (147, 160, 178)

_FONT_CANDIDATES = [
    ("/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc", 0),
    ("/usr/share/fonts/opentype/unifont/unifont_jp.otf", None),
    ("/usr/share/fonts/truetype/fonts-japanese-gothic.ttf", None),
]


def _font(size: int):
    for path, idx in _FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=idx) if idx is not None else ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def _wrap(draw, text, font, max_w):
    """日本語向け：1文字ずつ幅を測って折り返す。"""
    lines, cur = [], ""
    for ch in text:
        if ch == "\n":
            lines.append(cur); cur = ""; continue
        test = cur + ch
        if draw.textlength(test, font=font) > max_w and cur:
            lines.append(cur); cur = ch
        else:
            cur = test
    if cur:
        lines.append(cur)
    return lines


def _draw_center(draw, lines, font, cx, top, fill, line_gap=1.35):
    y = top
    for ln in lines:
        w = draw.textlength(ln, font=font)
        draw.text((cx - w / 2, y), ln, font=font, fill=fill)
        y += int(font.size * line_gap)
    return y


def render_scene(scene, size, out_path, ep, total, index):
    W, H = size
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # 上部：EPラベル＋進行
    lab = _font(int(W * 0.030))
    d.text((int(W * 0.06), int(H * 0.045)), f"EP{ep:02d}", font=lab, fill=ACCENT)
    prog = f"{index}/{total}"
    d.text((W - int(W * 0.06) - d.textlength(prog, font=lab), int(H * 0.045)), prog, font=lab, fill=MUTED)

    # 中央：テロップ（大）
    telop = scene.get("telop", "")
    tf = _font(int(W * 0.085))
    lines = _wrap(d, telop, tf, int(W * 0.86))
    total_h = len(lines) * int(tf.size * 1.35)
    top = (H - total_h) // 2 - int(H * 0.04)
    # ロールで色分け（hook/ctaはアンバー、他はティール）
    color = AMBER if scene.get("role") in ("hook", "cta") else ACCENT
    # アクセントの下線バー
    d.rectangle([int(W * 0.08), top - int(H * 0.03), int(W * 0.08) + int(W * 0.16), top - int(H * 0.023)], fill=color)
    _draw_center(d, lines, tf, W // 2, top, FG)

    # 下部：チャンネル名
    cf = _font(int(W * 0.030))
    ch = "お金の失敗検証チャンネル"
    d.text((W // 2 - d.textlength(ch, font=cf) / 2, int(H * 0.93)), ch, font=cf, fill=MUTED)

    img.save(out_path)
    return out_path


def render_thumbnail(title, out_path, size=(1280, 720)):
    W, H = size
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # 左に警告数字、右にタイトル要約
    big = _font(150)
    d.text((60, 210), "毎年", font=_font(70), fill=MUTED)
    d.text((60, 280), "減る", font=big, fill=AMBER)
    tf = _font(64)
    lines = _wrap(d, "銀行のお金\nそのままで大丈夫？", tf, int(W * 0.5))
    _draw_center(d, lines, tf, int(W * 0.72), 250, FG)
    d.rectangle([0, H - 16, W, H], fill=ACCENT)
    img.save(out_path)
    return out_path
