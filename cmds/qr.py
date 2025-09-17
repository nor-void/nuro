#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# pip 依存（nuro 側の自動解決を想定）
__requires__ = ["qrcode[pil]>=7.4", "Pillow>=9"]

import sys
import argparse
import qrcode

# ターミナルの縦長比を補正するため、横方向を2倍に拡張し、行の縦方向はそのまま
# （必要なら --x2 や --scale で微調整可能）
def render_ascii(matrix, invert=False, x2=True, scale=1, border_pad=True):
    on, off = ("██", "  ") if not invert else ("  ", "██")
    lines = []
    W = len(matrix[0])
    pad = off * (W + 2) if border_pad else ""
    if border_pad:
        for _ in range(scale): lines.append(pad)
    for row in matrix:
        line = off if border_pad else ""
        for cell in row:
            line += (on if cell else off) * (2 if x2 else 1)
        if border_pad:
            # 右側余白（横拡張に合わせて倍）
            line += off * (2 if x2 else 1)
        for _ in range(scale):
            lines.append(line)
    if border_pad:
        for _ in range(scale): lines.append(pad)
    return "\n".join(lines)

def build_qr(text, border=2, version=None, ec="M"):
    ec_map = {
        "L": qrcode.constants.ERROR_CORRECT_L,
        "M": qrcode.constants.ERROR_CORRECT_M,
        "Q": qrcode.constants.ERROR_CORRECT_Q,
        "H": qrcode.constants.ERROR_CORRECT_H,
    }
    qr = qrcode.QRCode(
        version=version,
        error_correction=ec_map.get(ec.upper(), qrcode.constants.ERROR_CORRECT_M),
        box_size=10,
        border=border,
    )
    qr.add_data(text)
    qr.make(fit=True)
    return qr

def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    p = argparse.ArgumentParser(prog="nuro qr", description="Generate QR code (ASCII or PNG).")
    p.add_argument("text", help="Text or URL to encode")
    p.add_argument("-o", "--out", help="Save as PNG to this path (omit to print ASCII)")
    p.add_argument("--ec", choices=list("LMQH"), default="M", help="Error correction level (default: M)")
    p.add_argument("--border", type=int, default=2, help="Border modules (default: 2)")
    p.add_argument("--invert", action="store_true", help="Invert black/white in ASCII")
    p.add_argument("--no-x2", dest="x2", action="store_false", help="Disable horizontal x2 stretch")
    p.add_argument("--scale", type=int, default=1, help="Vertical line duplication (default: 1)")
    p.add_argument("--version", type=int, help="QR version (1-40). Omit for auto-fit.")
    args = p.parse_args(argv)

    qr = build_qr(args.text, border=args.border, version=args.version, ec=args.ec)

    if args.out:
        img = qr.make_image(fill_color="black", back_color="white")
        img.save(args.out)
        print(args.out)
        return

    matrix = qr.get_matrix()
    ascii_qr = render_ascii(matrix, invert=args.invert, x2=args.x2, scale=max(1, args.scale))
    print(ascii_qr)

if __name__ == "__main__":
    main()
