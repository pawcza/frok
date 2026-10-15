#!/usr/bin/env python3
"""news-fetch — headlines for the companion's news widget, as TSV lines:
<source>\t<title>\t<url>. Sources (comma-separated): "hn" for Hacker News'
top stories, or any RSS / Atom feed URL. Standard library only."""
import json, re, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
import xml.etree.ElementTree as ET

UA = {"User-Agent": "frok-companion (+https://github.com/pawcza/frok)"}

def get(url, timeout=8):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()

def tidy(s):  # one line, no control characters: it gets printed in a terminal
    return re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f\u0080-\u009f]+", " ", s or "")).strip()

def hacker_news(n=12):
    ids = json.loads(get("https://hacker-news.firebaseio.com/v0/topstories.json"))[:n]
    item = lambda i: json.loads(get(f"https://hacker-news.firebaseio.com/v0/item/{i}.json"))
    with ThreadPoolExecutor(6) as pool:          # one request per story: fetch them side by side
        for i, it in zip(ids, pool.map(item, ids)):
            yield "HN", it.get("title", ""), it.get("url") or f"https://news.ycombinator.com/item?id={i}"

def feed(url, n=12):
    root = ET.fromstring(get(url))
    strip = lambda t: t.split("}", 1)[-1]
    title = next((e.text for e in root.iter() if strip(e.tag) == "title"), url)
    src = re.sub(r"\s+", " ", title or "").strip()[:14]
    items = [e for e in root.iter() if strip(e.tag) in ("item", "entry")][:n]
    for it in items:
        t = next((c.text for c in it if strip(c.tag) == "title"), "")
        link = next((c.get("href") or c.text for c in it if strip(c.tag) == "link"), "")
        yield src, t, link

def main():
    for s in [s.strip() for s in (sys.argv[1] if len(sys.argv) > 1 else "hn").split(",") if s.strip()]:
        try:
            rows = hacker_news() if s == "hn" else feed(s)
            for src, t, link in rows:
                if t and link and re.match(r"https?://", link):
                    print(f"{tidy(src)}\t{tidy(t)}\t{tidy(link)}")
        except Exception as e:  # one bad feed shouldn't empty the widget
            print(f"news-fetch: {s}: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
