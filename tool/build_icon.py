"""アプリアイコンの元画像を生成する。

    python tool/build_icon.py
    flutter pub run flutter_launcher_icons

震源から広がる波を同心円で、位置を示す点を中心に置いた図案。
アプリの配色（ThemeData の seedColor）と揃えている。
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

SIZE = 1024
BACKGROUND = (0, 77, 64)  # 深い teal。アプリのテーマ色に合わせている
WAVE = (178, 223, 219)
CORE = (255, 255, 255)
ALERT = (239, 108, 0)  # 深刻度「警戒」の橙


def main() -> None:
    os.makedirs("assets/icon", exist_ok=True)

    image = Image.new("RGBA", (SIZE, SIZE), BACKGROUND + (255,))
    draw = ImageDraw.Draw(image)

    center = SIZE / 2
    # 震源から広がる波。外側ほど細く薄くして、伝わっていく感じを出す。
    for index, radius in enumerate((150, 250, 350)):
        width = 34 - index * 8
        draw.ellipse(
            [center - radius, center - radius, center + radius, center + radius],
            outline=WAVE,
            width=width,
        )

    # 震源（中心の点）
    core = 72
    draw.ellipse(
        [center - core, center - core, center + core, center + core],
        fill=CORE,
    )

    # 右上に警戒の印。ひと目で「災害の知らせ」と分かるようにする。
    badge = 120
    bx, by = SIZE - 250, 250
    draw.ellipse([bx - badge, by - badge, bx + badge, by + badge], fill=ALERT)
    draw.rounded_rectangle([bx - 18, by - 62, bx + 18, by + 22], 18, fill=CORE)
    draw.ellipse([bx - 20, by + 42, bx + 20, by + 82], fill=CORE)

    image.save("assets/icon/app_icon.png")

    # Android 8 以降のアダプティブアイコン用。前景は中央 66% に収める必要が
    # あるため、余白を広めに取った別画像にする。
    foreground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    inner = image.crop((160, 160, SIZE - 160, SIZE - 160)).resize((560, 560))
    mask = Image.new("L", (560, 560), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 560, 560], fill=255)
    foreground.paste(inner, (232, 232), mask)
    foreground.save("assets/icon/app_icon_foreground.png")

    print("assets/icon/app_icon.png と app_icon_foreground.png を作成しました")


if __name__ == "__main__":
    main()
