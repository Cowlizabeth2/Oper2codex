"""Small, safe formatting subset. Plain copy retains the original line endings."""
import html
import re


def presentation(config):
    text = config["text"]
    if config.get("format", "plain") == "plain":
        return {"plain": text, "html": html.escape(text).replace("\r\n", "\n").replace("\r", "\n").replace("\n", "<br>")}
    # No HTML, images or external resources are interpreted.
    plain, rich = [], []
    for line in text.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        ending = line[len(body):]
        heading = re.match(r"^(#{1,3}) (.*)$", body)
        if heading:
            body = heading[2]
        escaped = html.escape(body)
        for pattern, tag in [(r"\*\*(.+?)\*\*", "b"), (r"__(.+?)__", "u"), (r"(?<!\*)\*([^*]+)\*(?!\*)", "i")]:
            body = re.sub(pattern, r"\1", body)
            escaped = re.sub(pattern, rf"<{tag}>\1</{tag}>", escaped)
        if heading:
            escaped = "<b>" + escaped + "</b>"
        plain.append(body + ending)
        rich.append(escaped + ("<br>" if ending else ""))
    return {"plain": "".join(plain), "html": "".join(rich)}
