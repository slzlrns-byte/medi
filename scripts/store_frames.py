#!/usr/bin/env python3
"""App Store 등록용 그림을 만든다.

`ci/screenshots` 의 실캡처 위에 한 줄 문구를 얹어 1320×2868 로 낸다.
캡처 자체는 손대지 않는다 - 스토어 그림은 실제 앱과 같아야 하고(심사 2.3.3),
여기서 하는 일은 그 캡처를 줄여 앉히고 위에 말을 얹는 것뿐이다.

글꼴은 프리텐다드 Light. 앱이 본문에 쓰는 것과 같은 글꼴이고 저장소에
있다(OFL). 제목용 SUIT 도 써 봤지만 먼저 만든 그림과 다르게 보였다.

    python3 scripts/store_frames.py <캡처폴더> <낼폴더>
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# 제출 규격 6.9". 캡처와 같은 비율이라 가로를 맞추면 세로는 따라온다.
CANVAS = (1320, 2868)

# App Store Connect 의 아이폰 칸. 6.9" 는 새 앱에 필수이고, 나머지는 애플이
# 줄여서 쓰므로 선택이다. 그래도 같이 내는 이유: 6.5" 칸에 예전 그림이 남아
# 있으면 스토어가 기기에 따라 서로 다른 문구를 보여 준다.
# 6.9" 로 그린 뒤 통째로 줄인다 - 두 비율 차이가 0.4% 라 눈에 띄지 않는다.
SIZES = {
    "6.9": (1320, 2868),
    "6.5": (1242, 2688),
}
# 디자인 토큰의 fog / ink. 앱 배경과 같은 색이라 그림과 캡처가 이어져 보인다.
BACKGROUND = "#F7F7F6"
INK = "#1A1A19"
# 오늘 화면의 배경도 fog 라서, 테두리가 없으면 캡처가 바탕에 녹아 사라진다.
HAIRLINE = "#D4D4D1"

FONT = Path("TheJanjan/Resources/Fonts/GowunDodum-Regular.ttf")
FONT_SIZE = 104
LINE_HEIGHT = 150
# 문구 첫 줄 윗변.
CAPTION_TOP = 430
# 문구 아랫변과 캡처 윗변 사이.
CAPTION_GAP = 150

PHONE_WIDTH = 1150
CORNER_RADIUS = 72
SHADOW_BLUR = 28
SHADOW_DROP = 16

# 차례 · 문구 · 쓸 캡처. 문구의 줄바꿈은 손으로 정한다 - 한국어는 자동으로
# 끊으면 "먹었는지 / 바로" 처럼 어절 한가운데가 갈린다.
FRAMES = [
    ("01", "오늘 약, 먹었는지\n바로 알 수 있어요", "01-오늘"),
    ("02", "오늘의 기분은\n색으로 남겨요", "04-기록"),
    ("03", "남은 약 개수,\n더잔잔이 세고 있어요", "03-약-상세"),
    ("04", "약이 바뀌면,\n비교해 볼 수 있어요", "20-용량변경-전후"),
    ("05", "진료마다\n처방 기록을 남겨요", "08-처방-기록"),
    ("06", "빠트린 날은\n더잔잔이 함께 찾아요", "15-지나간-시간대"),
    ("07", "진료실에 들고 갈 한 장,\n미리 모아 둬요", "06-리포트"),
    ("08", "약 모양만 알아도\n찾을 수 있어요", "24-모양찾기"),
    ("09", "약 이름은\n가려 둘 수 있어요", "19-오늘-가림"),
    ("10", "필요하면 Pro 로,\n아니면 그대로 무료로", "26-구독"),
]


def find(folder: Path, stem: str) -> Path | None:
    """캡처 파일 이름에는 시뮬레이터 UUID 가 붙는다. 앞부분으로 찾는다."""
    matches = [
        path
        for path in sorted(folder.glob("*.png"))
        if path.name.startswith(stem + "_") or path.stem == stem
    ]
    # 좁은 화면(750×1334) 세트는 제출 규격이 아니다.
    wide = [path for path in matches if Image.open(path).size == CANVAS]
    return wide[0] if wide else None


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.size[0] - 1, image.size[1] - 1), radius=radius, fill=255
    )
    image = image.convert("RGBA")
    image.putalpha(mask)
    return image


def shadow(size: tuple[int, int], radius: int) -> Image.Image:
    """캡처 뒤에 깔 옅은 그림자. 번지는 만큼 사방으로 여유를 둔다."""
    pad = SHADOW_BLUR * 3
    layer = Image.new("L", (size[0] + pad * 2, size[1] + pad * 2), 0)
    ImageDraw.Draw(layer).rounded_rectangle(
        (pad, pad, pad + size[0], pad + size[1]), radius=radius, fill=70
    )
    return layer.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))


def compose(caption: str, shot: Path) -> Image.Image:
    canvas = Image.new("RGB", CANVAS, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(FONT), FONT_SIZE)

    lines = caption.split("\n")
    for index, line in enumerate(lines):
        box = draw.textbbox((0, 0), line, font=font)
        x = (CANVAS[0] - (box[2] - box[0])) // 2 - box[0]
        draw.text((x, CAPTION_TOP + index * LINE_HEIGHT), line, font=font, fill=INK)

    phone = Image.open(shot).convert("RGB")
    scale = PHONE_WIDTH / phone.size[0]
    phone = phone.resize(
        (PHONE_WIDTH, round(phone.size[1] * scale)), Image.LANCZOS
    )
    phone = rounded(phone, CORNER_RADIUS)
    # 머리카락 굵기 테두리. 바탕과 화면이 같은 색인 장면(오늘 화면)에서
    # 이것이 없으면 캡처가 어디서 시작하는지 보이지 않는다.
    ImageDraw.Draw(phone).rounded_rectangle(
        (0, 0, phone.size[0] - 1, phone.size[1] - 1),
        radius=CORNER_RADIUS, outline=HAIRLINE, width=3
    )

    left = (CANVAS[0] - PHONE_WIDTH) // 2
    top = CAPTION_TOP + len(lines) * LINE_HEIGHT + CAPTION_GAP

    pad = SHADOW_BLUR * 3
    canvas.paste(
        Image.new("RGB", (1, 1), INK).resize(phone.size),
        (left, top + SHADOW_DROP),
        shadow(phone.size, CORNER_RADIUS).crop(
            (pad, pad, pad + phone.size[0], pad + phone.size[1])
        ),
    )
    # 아래로 흘러 넘치게 둔다. 화면 전체를 다 보여 주는 것보다 위쪽 몇 줄이
    # 크게 읽히는 쪽이 스토어에서 잘 읽힌다.
    canvas.paste(phone, (left, top), phone)
    return canvas


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    target.mkdir(parents=True, exist_ok=True)

    missing = []
    for order, caption, stem in FRAMES:
        shot = find(source, stem)
        if shot is None:
            missing.append(f"{order} · {stem}")
            continue
        name = f"{order}-{caption.splitlines()[0].rstrip(',')}.png"
        image = compose(caption, shot)
        for label, size in SIZES.items():
            folder = target / label
            folder.mkdir(parents=True, exist_ok=True)
            page = image if size == CANVAS else image.resize(size, Image.LANCZOS)
            page.save(folder / name)
        print(f"{name}  ←  {shot.name}")

    for item in missing:
        print(f"제출 규격(1320×2868) 캡처가 없습니다: {item}", file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
