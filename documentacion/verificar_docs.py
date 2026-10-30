# -*- coding: utf-8 -*-
"""Verificación rápida: reabre cada .docx y resume su contenido."""

import glob
import os

from docx import Document

DIR = r"C:\DeepSeek Harness\libreriaAds\documentacion"

for f in sorted(glob.glob(os.path.join(DIR, "*.docx"))):
    d = Document(f)
    heads = [p.text for p in d.paragraphs if p.style.name in ("Title",) or p.style.name.startswith("Heading")]
    print(
        os.path.basename(f),
        "| parrafos:", len(d.paragraphs),
        "| tablas:", len(d.tables),
        "| titulo:", (heads[0] if heads else "(sin)"),
    )
