#!/usr/bin/env python3
# -*- coding: utf-8 -*-

__requires__ = ["googletrans==4.0.0-rc1"]

import sys
from googletrans import Translator

def main():
    if len(sys.argv) < 2:
        print("Usage: nuro trans <text> [lang]")
        sys.exit(1)

    text = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) > 2 else "en"

    translator = Translator()
    result = translator.translate(text, dest=target)
    print(result.text)

if __name__ == "__main__":
    main()

