#!/usr/bin/env python3
"""Fill the app's untranslated strings from the IronStack web's catalog.

For every translations/harbour-ironstack-<lang>.ts given, a message still
marked unfinished gets the web's translation when IronStack's
locale/<lang>/LC_MESSAGES/django.po has exactly the same text. Strings with
a format placeholder (%1, %n, %(name)s) are left alone: Qt's and Django's
placeholders differ. What's left is printed, to translate by hand.

    python3 -I tools/i18n/from-web.py ../IronStack sv et it ru

Only reads the IronStack checkout; nothing there is imported or executed.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def web_catalog(ironstack, lang):
    po = (ironstack / "locale" / lang / "LC_MESSAGES" / "django.po").read_text(encoding="utf-8")
    entries = {}
    for m in re.finditer(r'msgid ((?:"(?:[^"\\]|\\.)*"\s*)+)msgstr ((?:"(?:[^"\\]|\\.)*"\s*)+)', po):
        key = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))).replace('\\"', '"').replace("\\n", "\n")
        value = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))).replace('\\"', '"').replace("\\n", "\n")
        if value and "%" not in key:
            entries[key] = value
    return entries


def unescape(text):
    return (text.replace("&apos;", "'").replace("&quot;", '"').replace("&lt;", "<")
            .replace("&gt;", ">").replace("&amp;", "&"))


def escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("'", "&apos;").replace('"', "&quot;"))


def main():
    ironstack = pathlib.Path(sys.argv[1])
    for lang in sys.argv[2:]:
        path = ROOT / "translations" / f"harbour-ironstack-{lang}.ts"
        web = web_catalog(ironstack, lang)
        text = path.read_text(encoding="utf-8")
        left = []

        def fill(m):
            source = unescape(m.group(2))
            if source in web:
                return m.group(1) + "<translation>" + escape(web[source]) + "</translation>"
            left.append(source)
            return m.group(0)

        text = re.sub(r'(<source>([^<]*)</source>\s*(?:<extracomment>[^<]*</extracomment>\s*)?)'
                      r'<translation type="unfinished">[^<]*</translation>', fill, text)
        path.write_text(text, encoding="utf-8")
        print(f"{lang}: {len(left)} left to translate")
        for source in left:
            print("   ", source)


if __name__ == "__main__":
    main()
