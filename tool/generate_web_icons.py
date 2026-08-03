#!/usr/bin/env python3
"""توليد أيقونات الويب وشاشات البداية من شعار التطبيق.

## ليه الملف ده موجود؟

أيقونات `web/icons/` كانت لسه أيقونة Flutter الزرقاء الافتراضية اللي بتيجي
مع `flutter create`. يعني أي حد يثبّت التطبيق كان هيلاقي شعار Flutter على
شاشته الرئيسية بدل شعار DrD — وده أسوأ انطباع ممكن لتطبيق المفروض يوزَّع
بلينك.

## التشغيل

    pip install Pillow
    python3 tool/generate_web_icons.py

المخرجات كلها تحت `web/`.
"""

import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets" / "images" / "logo.png"
WEB = ROOT / "web"

# لون خلفية الشعار نفسه — يُقرأ من الصورة فلا يتفارق مع التصميم لو اتغيّر.
BRAND = None

# خلفية شاشة البداية: مطابقة لخلفية شاشة الإقلاع في index.html بالضبط،
# وإلا ظهرت وميضة لون بين الاتنين.
SPLASH_LIGHT = (245, 247, 250)   # #F5F7FA
SPLASH_DARK = (14, 20, 22)       # #0E1416


def load_logo():
    global BRAND
    logo = Image.open(LOGO).convert("RGBA")
    BRAND = logo.convert("RGB").getpixel((4, 4))
    return logo


def square_icon(logo, size):
    """أيقونة عادية — الشعار كامل بلا هوامش."""
    return logo.resize((size, size), Image.LANCZOS)


def maskable_icon(logo, size):
    """أيقونة قابلة للقص (maskable).

    أندرويد بيقص الأيقونة بأشكال مختلفة (دايرة، مربع مدوّر، معيّن...) حسب
    الجهاز. المنطقة المضمونة هي الدايرة الداخلية بنسبة 80% فقط، وأي محتوى
    بره الدايرة دي ممكن يتقص.

    الشعار الأصلي دايرته البيضا بتاخد ~82% من العرض — لو استُخدم كما هو
    هتتقص أطرافها. عشان كده بنصغّر المحتوى لـ 72% ونملا الباقي بلون
    الخلفية، فيفضل الشعار كامل مهما كان شكل القص.
    """
    canvas = Image.new("RGBA", (size, size), BRAND + (255,))
    inner = int(size * 0.72)
    resized = logo.resize((inner, inner), Image.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(resized, (offset, offset), resized)
    return canvas


def splash(logo, width, height, background):
    """شاشة بداية لـ iOS — خلفية سادة وشعار في المنتصف."""
    canvas = Image.new("RGB", (width, height), background)
    # 32% من أقصر ضلع: كبير بما يكفي ليُقرأ، وصغير بما يكفي ألا يبدو مقحماً.
    logo_size = int(min(width, height) * 0.32)
    resized = logo.resize((logo_size, logo_size), Image.LANCZOS)
    canvas.paste(
        resized,
        ((width - logo_size) // 2, (height - logo_size) // 2),
        resized,
    )
    return canvas


# مقاسات أجهزة الآيفون المتداولة (بكسل الجهاز، وضع رأسي).
# التغطية دي بتشمل الغالبية العظمى من الأجهزة الشغالة حالياً.
IPHONE_SIZES = [
    (1290, 2796),  # 15/16 Pro Max, 14 Pro Max
    (1179, 2556),  # 15/16, 14 Pro
    (1284, 2778),  # 12/13/14 Pro Max
    (1170, 2532),  # 12/13/14
    (1125, 2436),  # X, XS, 11 Pro
    (828, 1792),   # XR, 11
    (750, 1334),   # 8, SE (2nd/3rd)
]


def main():
    logo = load_logo()
    icons_dir = WEB / "icons"
    splash_dir = WEB / "splash"
    icons_dir.mkdir(parents=True, exist_ok=True)
    splash_dir.mkdir(parents=True, exist_ok=True)

    written = []

    for size in (192, 512):
        path = icons_dir / f"Icon-{size}.png"
        square_icon(logo, size).save(path, optimize=True)
        written.append(path)

        path = icons_dir / f"Icon-maskable-{size}.png"
        maskable_icon(logo, size).save(path, optimize=True)
        written.append(path)

    # أيقونة iOS للشاشة الرئيسية — سفاري بيستخدمها بدل الـ manifest.
    path = icons_dir / "apple-touch-icon.png"
    square_icon(logo, 180).save(path, optimize=True)
    written.append(path)

    # الأيقونة المصغّرة في تبويب المتصفح.
    path = WEB / "favicon.png"
    square_icon(logo, 32).save(path, optimize=True)
    written.append(path)

    for width, height in IPHONE_SIZES:
        for suffix, background in (
            ("light", SPLASH_LIGHT),
            ("dark", SPLASH_DARK),
        ):
            path = splash_dir / f"splash-{width}x{height}-{suffix}.png"
            splash(logo, width, height, background).save(path, optimize=True)
            written.append(path)

    total = sum(p.stat().st_size for p in written)
    for p in written:
        print(f"  {p.relative_to(ROOT)}  ({p.stat().st_size:,} بايت)")
    print(f"\n✅ تم توليد {len(written)} ملف — الإجمالي {total / 1024:.0f} كيلوبايت")


if __name__ == "__main__":
    main()
