# -*- coding: utf-8 -*-
"""Genera documentos Word (.docx) a partir de la documentación Markdown.

Convierte PROTOCOL.md y los manuales de docs/ en .docx con estilos de
encabezado, tablas, listas y bloques de código en fuente monoespaciada.
"""

import os
import re

from docx import Document
from docx.shared import Pt, Inches

SRC_DIR = r"C:\DeepSeek Harness\libreriaAds"
OUT_DIR = r"C:\DeepSeek Harness\libreriaAds\documentacion"

DOCS = [
    ("PROTOCOL.md", "protocolo-ads.docx"),
    ("docs/01-arquitectura.md", "01-arquitectura.docx"),
    ("docs/02-manual-python.md", "02-manual-python.docx"),
    ("docs/03-manual-csharp.md", "03-manual-csharp.docx"),
    ("docs/04-manual-simulador.md", "04-manual-simulador.docx"),
    ("docs/05-guia-integracion.md", "05-guia-integracion.docx"),
    ("docs/06-manual-tramas.md", "06-manual-tramas.docx"),
    ("docs/07-manual-programador.md", "07-manual-programador.docx"),
]

INLINE_RE = re.compile(r"(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)]*\))")


def is_table_separator(line):
    s = line.strip()
    if "|" not in s:
        return False
    core = s.replace("|", "").replace(" ", "")
    return len(core) > 0 and all(c in "-:" for c in core)


def add_inline(paragraph, text):
    """Añade runs a un párrafo interpretando **negrita**, `código` y [enlace]."""
    for part in INLINE_RE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            run = paragraph.add_run(part[2:-2])
            run.bold = True
        elif part.startswith("`") and part.endswith("`"):
            run = paragraph.add_run(part[1:-1])
            run.font.name = "Consolas"
            run.font.size = Pt(9.5)
        elif part.startswith("[") and "](" in part:
            m = re.match(r"\[([^\]]+)\]\(([^)]*)\)", part)
            if m:
                paragraph.add_run(m.group(1))
            else:
                paragraph.add_run(part)
        else:
            paragraph.add_run(part)


def clean_heading(text):
    return re.sub(r"[*`]", "", text)


def convert(md_path, docx_path):
    with open(md_path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    doc = Document()
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()

        # Bloque de código delimitado por ```.
        if stripped.startswith("```"):
            code_lines = []
            i += 1
            while i < n and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            i += 1  # salta el cierre ```
            for cl in code_lines:
                p = doc.add_paragraph()
                p.paragraph_format.left_indent = Inches(0.3)
                p.paragraph_format.space_after = Pt(0)
                run = p.add_run(cl if cl else " ")
                run.font.name = "Consolas"
                run.font.size = Pt(9)
            continue

        # Tabla: línea con | seguida de separador ---.
        if stripped.startswith("|") and i + 1 < n and is_table_separator(lines[i + 1]):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip())
                i += 1
            rows = [r for r in rows if not is_table_separator(r)]

            def split_row(r):
                r = r.strip()
                if r.startswith("|"):
                    r = r[1:]
                if r.endswith("|"):
                    r = r[:-1]
                return [c.strip() for c in r.split("|")]

            header = split_row(rows[0])
            body = [split_row(r) for r in rows[1:]]
            table = doc.add_table(rows=1 + len(body), cols=len(header))
            table.style = "Table Grid"
            for j, h in enumerate(header):
                cell = table.rows[0].cells[j]
                cell.text = h
                for para in cell.paragraphs:
                    for run in para.runs:
                        run.bold = True
            for ri, row in enumerate(body):
                for j in range(len(header)):
                    val = row[j] if j < len(row) else ""
                    cell = table.rows[ri + 1].cells[j]
                    cell.text = ""
                    add_inline(cell.paragraphs[0], val)
            doc.add_paragraph()
            continue

        # Encabezados.
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1)) - 1  # '#' -> Title (0), '##' -> Heading 1, ...
            doc.add_heading(clean_heading(m.group(2).strip()), level=level)
            i += 1
            continue

        # Lista con viñetas.
        m = re.match(r"^[-*]\s+(.*)$", stripped)
        if m:
            p = doc.add_paragraph(style="List Bullet")
            add_inline(p, m.group(1))
            i += 1
            continue

        # Lista numerada.
        m = re.match(r"^\d+\.\s+(.*)$", stripped)
        if m:
            p = doc.add_paragraph(style="List Number")
            add_inline(p, m.group(1))
            i += 1
            continue

        # Regla horizontal o línea vacía.
        if not stripped or stripped == "---":
            i += 1
            continue

        # Párrafo normal.
        p = doc.add_paragraph()
        add_inline(p, stripped)
        i += 1

    doc.save(docx_path)
    return docx_path


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for rel_md, docx_name in DOCS:
        md_path = os.path.join(SRC_DIR, rel_md)
        docx_path = os.path.join(OUT_DIR, docx_name)
        convert(md_path, docx_path)
        print("Generado:", docx_path)


if __name__ == "__main__":
    main()
