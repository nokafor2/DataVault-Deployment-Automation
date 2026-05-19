"""Generate DataVault Platform Guide PDF from Markdown source."""
from pathlib import Path
from fpdf import FPDF


def sanitize(text: str) -> str:
    """Map Unicode punctuation to ASCII for core PDF fonts."""
    replacements = {
        "\u2014": "-", "\u2013": "-", "\u2022": "*",
        "\u2192": "->", "\u2018": "'", "\u2019": "'",
        "\u201c": '"', "\u201d": '"', "\u00a3": "GBP ",
        "\u2500": "-", "\u2502": "|", "\u251c": "+", "\u2514": "+",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text.encode("latin-1", errors="replace").decode("latin-1")


def write_wrapped(pdf: FPDF, text: str, h: float = 5, font_size: int = 10) -> None:
    """Write text with word wrap; break very long tokens."""
    pdf.set_font("Helvetica", "", font_size)
    max_w = pdf.w - pdf.l_margin - pdf.r_margin
    for word in text.split(" "):
        while pdf.get_string_width(word) > max_w - 2:
            chunk = word[: int(max_w / font_size * 2)]
            pdf.multi_cell(0, h, chunk)
            word = word[len(chunk) :]
        if word:
            pdf.write(h, word + " ")
    pdf.ln(h)


class GuidePDF(FPDF):
    def header(self):
        if self.page_no() > 1:
            self.set_font("Helvetica", "I", 8)
            self.set_text_color(100, 100, 100)
            self.cell(0, 8, "DataVault Deployment Automation Platform", align="C", new_x="LMARGIN", new_y="NEXT")
            self.ln(2)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(100, 100, 100)
        self.cell(0, 10, f"Page {self.page_no()}", align="C")


def render_markdown_to_pdf(md_path: Path, pdf_path: Path) -> None:
    pdf = GuidePDF()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()
    pdf.set_margins(20, 20, 20)

    def content_width() -> float:
        return pdf.w - pdf.l_margin - pdf.r_margin

    def writeln(text: str, h: float = 5, style: str = "", size: int = 10) -> None:
        pdf.set_x(pdf.l_margin)
        pdf.set_font("Helvetica", style, size)
        pdf.multi_cell(content_width(), h, sanitize(text))

    lines = md_path.read_text(encoding="utf-8").splitlines()
    in_code = False
    code_buffer: list[str] = []

    def flush_code():
        nonlocal code_buffer
        if not code_buffer:
            return
        pdf.set_font("Courier", "", 7)
        pdf.set_fill_color(245, 245, 245)
        max_w = content_width()
        for line in code_buffer:
            safe = sanitize(line.replace("\t", "    "))
            if not safe.strip():
                pdf.ln(2)
                continue
            if pdf.get_y() > pdf.h - 25:
                pdf.add_page()
            pdf.multi_cell(max_w, 3.5, safe, fill=True)
        pdf.ln(2)
        code_buffer = []

    for raw in lines:
        line = raw.rstrip()

        if line.strip().startswith("```"):
            if in_code:
                flush_code()
                in_code = False
            else:
                in_code = True
            continue

        if in_code:
            code_buffer.append(line)
            continue

        if line.strip() == "---":
            pdf.ln(3)
            pdf.set_draw_color(200, 200, 200)
            pdf.line(20, pdf.get_y(), 190, pdf.get_y())
            pdf.ln(5)
            continue

        if not line.strip():
            pdf.ln(3)
            continue

        if line.startswith("# "):
            pdf.ln(4)
            pdf.set_font("Helvetica", "B", 18)
            pdf.set_text_color(20, 60, 120)
            writeln(line[2:].strip(), h=10, style="B", size=18)
            pdf.set_text_color(0, 0, 0)
            continue

        if line.startswith("## "):
            pdf.ln(3)
            pdf.set_font("Helvetica", "B", 14)
            pdf.set_text_color(30, 80, 140)
            writeln(line[3:].strip(), h=8, style="B", size=14)
            pdf.set_text_color(0, 0, 0)
            continue

        if line.startswith("### "):
            pdf.ln(2)
            pdf.set_font("Helvetica", "B", 11)
            writeln(line[4:].strip(), h=7, style="B", size=11)
            continue

        if line.startswith("|") and "|" in line[1:]:
            pdf.set_font("Courier", "", 8)
            pdf.set_x(pdf.l_margin)
            pdf.set_font("Courier", "", 8)
            pdf.multi_cell(content_width(), 4, sanitize(line))
            continue

        if line.startswith("- ") or line.startswith("* "):
            writeln("  *  " + line[2:].strip())
            continue

        if len(line) > 2 and line[0].isdigit() and ". " in line[:5]:
            writeln("  " + line.strip())
            continue

        text = line.strip()
        if text.startswith("**") and text.endswith("**"):
            writeln(text.strip("*"), style="B")
        else:
            writeln(text.replace("**", "").replace("`", ""))

    flush_code()
    pdf.output(str(pdf_path))
    print(f"PDF written to: {pdf_path}")


if __name__ == "__main__":
    base = Path(__file__).parent
    render_markdown_to_pdf(
        base / "DataVault-Platform-Guide.md",
        base / "DataVault-Platform-Guide.pdf",
    )
