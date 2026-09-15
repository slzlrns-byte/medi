#!/usr/bin/env python3
"""식약처 '의약품 낱알식별 정보' 를 받아 pill_catalog.json 을 만든다.

출처: 공공데이터포털 data.go.kr 데이터셋 15057639 (식품의약품안전처).
      공공누리 제1유형(출처표시) 기준 - 텍스트 항목만 담고, 낱알 사진은
      재배포 권리가 확실치 않아 번들에 넣지 않는다(URL 만 보관).

돌리는 곳: GitHub Actions (개발 컨테이너는 *.go.kr 이 막혀 있다).
필요한 것: 환경변수 MFDS_SERVICE_KEY - 공공데이터포털에서 이 API 활용신청 후
받는 일반 인증키(Decoding 값). 저장소 시크릿으로 넣는다.

전 품목(약 2만)을 다 싣지 않는다. 정신과 진료에서 만날 법한 것만 추린다:
  · 분류번호가 중추신경계 계열(112 최면진정, 113 항전간, 116 항파킨슨,
    117 정신신경용, 119 기타 중추신경)이거나
  · 품목명에 앱의 성분명 표(DrugNames.swift)에 있는 성분이 들어 있는 것.
"""

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRUG_NAMES_SWIFT = os.path.join(
    REPO_ROOT, "Packages/JanjanCore/Sources/JanjanCore/Catalog/DrugNames.swift"
)
OUTPUT = os.path.join(
    REPO_ROOT, "Packages/JanjanCore/Sources/JanjanCore/Resources/pill_catalog.json"
)

# 버전이 갈아엎어질 때를 대비해 알려진 판을 차례로 두드린다.
ENDPOINTS = [
    "https://apis.data.go.kr/1471000/MdcinGrnIdntfcInfoService03/getMdcinGrnIdntfcInfoList03",
    "https://apis.data.go.kr/1471000/MdcinGrnIdntfcInfoService02/getMdcinGrnIdntfcInfoList02",
    "https://apis.data.go.kr/1471000/MdcinGrnIdntfcInfoService01/getMdcinGrnIdntfcInfoList01",
]

# 분류번호 "01170" 의 가운데 세 자리가 분류다. 정신과 진료에서 만날 법한 계열만.
KEEP_CLASS3 = {"112", "113", "116", "117", "119"}

# 식약처 표준 모양 → PillFinder.Shape rawValue
SHAPE_MAP = {
    "원형": "round",
    "타원형": "oval",
    "장방형": "oblong",
    "삼각형": "triangle",
    "사각형": "square",
    "마름모형": "diamond",
    "마름모": "diamond",
    "오각형": "pentagon",
    "육각형": "hexagon",
    "팔각형": "octagon",
    "반원형": "other",
    "기타": "other",
}

# 식약처 표준 색 → PillFinder.PillColor rawValue
COLOR_MAP = {
    "하양": "white", "흰색": "white",
    "노랑": "yellow",
    "주황": "orange",
    "분홍": "pink",
    "빨강": "red",
    "갈색": "brown",
    "연두": "lightGreen",
    "초록": "green",
    "청록": "teal",
    "파랑": "blue",
    "남색": "navy",
    "자주": "wine",
    "보라": "purple",
    "회색": "gray",
    "검정": "black",
    "투명": "clear",
}


def load_generic_names():
    """DrugNames.swift 의 ("한글", "영어") 짝에서 한글 성분명을 뽑는다."""
    with open(DRUG_NAMES_SWIFT, encoding="utf-8") as f:
        source = f.read()
    pairs = re.findall(r'\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)', source)
    names = [ko for ko, _ in pairs if re.search(r"[가-힣]", ko)]
    if len(names) < 30:
        sys.exit(f"DrugNames.swift 에서 성분명을 {len(names)}개밖에 못 읽었습니다. 정규식을 확인하세요.")
    return names


def fetch_page(endpoint, service_key, page):
    params = urllib.parse.urlencode({
        "serviceKey": service_key,
        "type": "json",
        "numOfRows": 100,
        "pageNo": page,
    })
    request = urllib.request.Request(f"{endpoint}?{params}", headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read().decode("utf-8")
    if raw.lstrip().startswith("<"):
        # 인증 실패 등은 XML 오류로 온다. 원문 머리를 그대로 보여 준다.
        raise RuntimeError(f"JSON 이 아닌 응답: {raw[:300]}")
    return json.loads(raw)


def normalize_keys(item):
    """API 판마다 키 표기가 다르다(ITEM_IMAGE / itemImage / item_image).
    소문자로 내리고 밑줄을 지워 어느 표기든 같은 키로 읽는다."""
    return {re.sub(r"[^a-z0-9]", "", key.lower()): value for key, value in item.items()}


def pick(norm, *keys):
    for key in keys:
        value = norm.get(re.sub(r"[^a-z0-9]", "", key.lower()))
        if value not in (None, "", "null"):
            return str(value).strip()
    return ""


def first_color(text):
    for token in re.split(r"[,/·\s]+", text):
        if token in COLOR_MAP:
            return COLOR_MAP[token]
    return None


def class3(class_no):
    digits = re.sub(r"\D", "", class_no)
    if len(digits) < 4:
        return ""
    return digits.zfill(5)[1:4]


def convert(item, generic_names):
    norm = normalize_keys(item)
    name = pick(norm, "ITEM_NAME")
    seq = pick(norm, "ITEM_SEQ")
    if not name or not seq:
        return None, "이름/번호 없음"

    keep = class3(pick(norm, "CLASS_NO")) in KEEP_CLASS3 \
        or any(generic in name for generic in generic_names)
    if not keep:
        return None, "분류 밖"

    shape_text = pick(norm, "DRUG_SHAPE")
    form_text = pick(norm, "FORM_CODE_NAME")
    if "캡슐" in form_text or "캡슐" in shape_text:
        shape = "capsule"
    else:
        shape = SHAPE_MAP.get(shape_text)
    if shape is None:
        return None, f"모양 미지원({shape_text})"

    color_front = first_color(pick(norm, "COLOR_CLASS1"))
    if color_front is None:
        return None, f"색 미지원({pick(norm, 'COLOR_CLASS1')})"
    color_back = first_color(pick(norm, "COLOR_CLASS2"))

    pill = {
        "id": seq,
        "name": name,
        "strengthText": "",
        "shape": shape,
        "colorFront": color_front,
        "imprintFront": pick(norm, "PRINT_FRONT"),
        "imprintBack": pick(norm, "PRINT_BACK"),
    }
    if color_back and color_back != color_front:
        pill["colorBack"] = color_back
    # 사진은 식약처 서버 URL 만 담는다. 파일을 받아 번들에 넣지 않는다 -
    # 실제 촬영 주체(약학정보원)의 권리가 완전히 정리되지 않은 회색지대라서,
    # 화면은 이 URL 을 그때그때 불러와 보여 주기만 한다.
    image = pick(norm, "ITEM_IMAGE")
    if image.startswith("http"):
        pill["imageURLString"] = image
    return pill, None


def main():
    service_key = os.environ.get("MFDS_SERVICE_KEY", "").strip()
    if not service_key:
        sys.exit("MFDS_SERVICE_KEY 가 비어 있습니다. 공공데이터포털 인증키를 시크릿으로 넣어 주세요.")

    generic_names = load_generic_names()

    endpoint = None
    first = None
    for candidate in ENDPOINTS:
        try:
            first = fetch_page(candidate, service_key, 1)
            body = first.get("body") or first.get("response", {}).get("body")
            if body and int(body.get("totalCount", 0)) > 0:
                endpoint = candidate
                break
            print(f"응답에 body/totalCount 없음: {candidate} → {str(first)[:200]}")
        except Exception as error:  # noqa: BLE001 - 어떤 실패든 다음 판을 시도한다
            print(f"실패: {candidate} → {error}")
    if endpoint is None:
        sys.exit("어느 엔드포인트에서도 데이터를 받지 못했습니다. 위 로그를 확인하세요.")

    body = first.get("body") or first.get("response", {}).get("body")
    total = int(body["totalCount"])
    print(f"엔드포인트: {endpoint}")
    print(f"전체 품목: {total}")

    def items_of(payload):
        payload_body = payload.get("body") or payload.get("response", {}).get("body") or {}
        items = payload_body.get("items") or []
        # data.go.kr 은 {"items":{"item":[...]}} 로 감싸기도 한다.
        if isinstance(items, dict):
            items = items.get("item") or []
        if isinstance(items, dict):
            items = [items]
        return items

    pills = {}
    skipped = {}
    page = 1
    seen = 0
    while seen < total:
        payload = first if page == 1 else fetch_page(endpoint, service_key, page)
        items = items_of(payload)
        if not items:
            break
        for item in items:
            seen += 1
            pill, reason = convert(item, generic_names)
            if pill is not None:
                pills[pill["id"]] = pill
            elif reason != "분류 밖":
                skipped[reason] = skipped.get(reason, 0) + 1
        page += 1
        time.sleep(0.15)  # 공공 API 를 몰아치지 않는다

    result = sorted(pills.values(), key=lambda pill: pill["name"])
    print(f"읽음 {seen} / 담음 {len(result)} / 조건 밖 제외는 정상 동작")
    for reason, count in sorted(skipped.items()):
        print(f"  건너뜀 {count}: {reason}")

    if len(result) < 200:
        sys.exit(f"담은 품목이 {len(result)}개뿐입니다. 필드명이나 필터가 어긋났을 수 있어 중단합니다.")

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    size_kb = os.path.getsize(OUTPUT) // 1024
    print(f"저장: {os.path.relpath(OUTPUT, REPO_ROOT)} ({size_kb}KB)")


if __name__ == "__main__":
    main()
