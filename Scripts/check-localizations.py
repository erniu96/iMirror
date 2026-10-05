#!/usr/bin/env python3
"""Checks that every localization matches the English strings and the code.

- Every string the code looks up must exist in Resources/en.lproj.
- Every English string must still be used by the code.
- Every other <language>.lproj must have exactly the English keys, with the
  same format specifiers (%@, %lld, %d; positional forms such as %1$@ count
  as the plain specifier).
- User-facing source files must not contain hard-coded Chinese text.

Runs anywhere with Python 3; no Xcode needed.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
SOURCE_DIRS = ["App", "Audio", "Bridge", "Domain", "Services", "Storage", "Video", "Window"]

SWIFT_STRING = r'"((?:[^"\\\n]|\\.)*)"'
SWIFT_PATTERNS = [
    re.compile(r'String\(localized:\s*' + SWIFT_STRING),
    # SwiftUI initializers whose first string literal is a LocalizedStringKey.
    re.compile(r'\b(?:Text|Button|Toggle|Label|Section|TextField|LabeledContent|confirmationDialog)\(\s*' + SWIFT_STRING),
    re.compile(r'\bstep\(\s*\d+,\s*title:\s*' + SWIFT_STRING),
]
OBJC_PATTERN = re.compile(r'NSLocalizedString\(\s*@' + SWIFT_STRING)
STRINGS_ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
SPECIFIER = re.compile(r'%(?:\d+\$)?(lld|ld|d|@|f|%)')


def unescape(text):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), text)


def swift_key(literal):
    """Turns a Swift literal with interpolations into its localization key."""
    def replace(match):
        expression = match.group(1).strip()
        integer = expression.startswith("Int(") or expression.endswith(".count")
        return "%lld" if integer else "%@"
    return unescape(re.sub(r'\\\(((?:[^()]|\([^()]*\))*)\)', replace, literal))


def used_keys():
    keys = {}
    for directory in SOURCE_DIRS:
        for path in sorted((ROOT / directory).glob("*")):
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".swift":
                for pattern in SWIFT_PATTERNS:
                    for match in pattern.finditer(text):
                        key = swift_key(match.group(1))
                        if SPECIFIER.sub("", key).strip():
                            keys.setdefault(key, f"{path.relative_to(ROOT)}")
            elif path.suffix in (".m", ".mm"):
                for match in OBJC_PATTERN.finditer(text):
                    keys.setdefault(unescape(match.group(1)), f"{path.relative_to(ROOT)}")
    return keys


def read_strings(path):
    entries = {}
    in_comment = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if in_comment:
            in_comment = "*/" not in stripped
            continue
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.startswith("/*"):
            in_comment = "*/" not in stripped
            continue
        match = STRINGS_ENTRY.match(line)
        if not match:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: 无法解析 / cannot parse: {line}")
        key, value = unescape(match.group(1)), unescape(match.group(2))
        if key in entries:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: 重复的 key / duplicate key: {key}")
        entries[key] = value
    return entries


def specifiers(text):
    return sorted(m.group(1) for m in SPECIFIER.finditer(text))


def main():
    problems = []
    languages = sorted(p for p in RESOURCES.glob("*.lproj"))
    tables = {}
    for language in languages:
        for table in ("Localizable.strings", "InfoPlist.strings"):
            path = language / table
            try:
                tables[(language.stem, table)] = read_strings(path) if path.exists() else None
            except ValueError as error:
                problems.append(str(error))
    if problems:
        print("\n".join(problems))
        return 1

    english = tables.get(("en", "Localizable.strings"))
    if english is None:
        print("缺少 Resources/en.lproj/Localizable.strings")
        return 1

    for key, source in used_keys().items():
        if key not in english:
            problems.append(f"en: 代码使用了未登记的字符串 / missing key used in {source}: {key!r}")
    unused = set(english) - set(used_keys())
    for key in sorted(unused):
        problems.append(f"en: 代码不再使用的字符串 / unused key: {key!r}")

    for table in ("Localizable.strings", "InfoPlist.strings"):
        reference = tables.get(("en", table))
        if reference is None:
            continue
        for language in languages:
            if language.stem == "en":
                continue
            translation = tables.get((language.stem, table))
            if translation is None:
                problems.append(f"{language.stem}: 缺少 {table} / missing {table}")
                continue
            for key in sorted(set(reference) - set(translation)):
                problems.append(f"{language.stem}/{table}: 缺少翻译 / missing translation: {key!r}")
            for key in sorted(set(translation) - set(reference)):
                problems.append(f"{language.stem}/{table}: 多余的 key / extra key: {key!r}")
            for key in sorted(set(reference) & set(translation)):
                if specifiers(reference[key]) != specifiers(translation[key]):
                    problems.append(f"{language.stem}/{table}: 格式占位符不一致 / format specifiers differ: {key!r}")
                if not translation[key].strip():
                    problems.append(f"{language.stem}/{table}: 翻译为空 / empty translation: {key!r}")

    plist = (RESOURCES / "Info.plist").read_text(encoding="utf-8")
    declared = re.search(r"<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>", plist, re.S)
    declared = set(re.findall(r"<string>([^<]+)</string>", declared.group(1))) if declared else set()
    present = {language.stem for language in languages}
    if declared != present:
        problems.append(f"Info.plist 的 CFBundleLocalizations {sorted(declared)} 与 Resources 中的语言 {sorted(present)} 不一致 / CFBundleLocalizations does not match the .lproj folders")

    for directory in SOURCE_DIRS:
        for path in sorted((ROOT / directory).glob("*")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("//", 1)[0]
                if re.search("[一-鿿]", code):
                    problems.append(f"{path.relative_to(ROOT)}:{number}: 硬编码的中文 / hard-coded Chinese text: {line.strip()}")

    if problems:
        print("\n".join(problems))
        print(f"\n本地化检查失败：{len(problems)} 项 / Localization check failed: {len(problems)} problem(s)")
        return 1
    print(f"✓ 本地化检查通过 / Localizations OK: {', '.join(sorted(present))}，{len(english)} 条字符串 / strings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
